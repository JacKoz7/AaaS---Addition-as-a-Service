-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       successor
-- Module:          Successor.CallLog
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         The successor's own CouchDB database: migrations at
--                  startup and the call log with one document per call of a
--                  task.
-- Related Docs:    services/successor/migrations/, services/successor/README.md,
--                  CLAUDE.md 3 (step 7) and 6.1, ADR-0016

-- | CouchDB call log.
--
-- __Description:__ The database @successor_calls@ holds one document per
-- successor call, with the natural key @\<taskId\>:\<n\>@: an addition calls
-- the successor of every value between @a@ and @a + b - 1@ exactly once,
-- so the key identifies a call, and a retried call finds its own
-- document instead of writing a second one. The document stores the
-- serialized event, which a retry publishes again unchanged.
--
-- Migrations are JSON files in @migrations/@ (CouchDB has no DDL); each is
-- a list of idempotent operations, applied in file-name order at startup
-- and recorded as a document in @successor_migrations@.
--
-- Every HTTP call has a 250 ms timeout and is attempted three times with
-- jittered backoff (50 ms, 100 ms), keeping a call within the 1.8 s
-- request budget (ADR-0016). Authentication is HTTP Basic: CouchDB 3.5
-- caches the verified credentials, so it costs no more than a session
-- cookie (measured 4 ms per write either way).
--
-- __Business Justification:__ Every successor call is logged in CouchDB
-- (CLAUDE.md 3, step 7); every service owns its database (CLAUDE.md 1,
-- rule 4).
--
-- __Thread Safety:__ safe; the HTTP manager is shared between requests.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
module Successor.CallLog
  ( CallLog,
    CallLogError (..),
    CallRecord (..),
    RecordResult (..),
    callsDatabase,
    migrationsDatabase,
    documentId,
    newCallLog,
    ping,
    migrate,
    record,
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception (Exception, SomeException, fromException, throwIO, try)
import Control.Monad (foldM, forM_, void)
import Data.Aeson (FromJSON (..), ToJSON (..), Value, object, withObject, (.:), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as BL
import Data.List (sort)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TE
import Network.HTTP.Client
  ( HttpException (HttpExceptionRequest),
    Manager,
    Request (..),
    RequestBody (RequestBodyLBS),
    applyBasicAuth,
    defaultManagerSettings,
    httpLbs,
    managerResponseTimeout,
    newManager,
    parseRequest,
    responseBody,
    responseStatus,
    responseTimeoutMicro,
  )
import Network.HTTP.Types (statusCode, urlEncode)
import Successor.Identifiers (formatTimestamp, nowMillis)
import System.Directory (listDirectory)
import System.FilePath (dropExtension, takeExtension, (</>))
import System.Random (randomRIO)

-- | A connection to the service's CouchDB.
--
-- __Description:__ Base URL, credentials and the shared HTTP manager.
--
-- __Business Justification:__ Built once at startup by 'newCallLog'.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data CallLog = CallLog
  { manager :: Manager,
    baseUrl :: Text,
    user :: ByteString,
    password :: ByteString
  }

-- | A CouchDB failure after all attempts.
--
-- __Description:__ The message names the operation and the cause (status
-- code or exception); credentials are never included.
--
-- __Business Justification:__ One exception type the service turns into
-- a 503 problem.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
newtype CallLogError = CallLogError Text
  deriving stock (Show)

-- | 'CallLogError' is thrown with 'throwIO'.
instance Exception CallLogError

-- | One logged successor call.
--
-- __Description:__ The document stored under 'documentId'; the
-- serialized event is kept as text in @event@.
--
-- __Business Justification:__ The audit record of CLAUDE.md 3, step 7,
-- and the source of a republished event.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data CallRecord = CallRecord
  { -- | Task of the call (lowercase UUID).
    recTaskId :: Text,
    -- | Argument of the call.
    recN :: Integer,
    -- | Result, @n + 1@.
    recResult :: Integer,
    -- | @eventId@ of the published event.
    recEventId :: Text,
    -- | The published event, exactly as sent.
    recEvent :: Text,
    -- | When the call was first served (AaaS timestamp).
    recCalledAt :: Text,
    -- | Trace of the first request.
    recTraceId :: Text
  }
  deriving stock (Eq, Show)

-- | JSON form of a 'CallRecord' as stored in CouchDB.
instance ToJSON CallRecord where
  toJSON r =
    object
      [ "taskId" .= recTaskId r,
        "n" .= recN r,
        "result" .= recResult r,
        "eventId" .= recEventId r,
        "event" .= recEvent r,
        "calledAt" .= recCalledAt r,
        "traceId" .= recTraceId r
      ]

-- | Reads a stored document; CouchDB's @_id@ and @_rev@ are ignored.
instance FromJSON CallRecord where
  parseJSON = withObject "CallRecord" $ \o ->
    CallRecord
      <$> o .: "taskId"
      <*> o .: "n"
      <*> o .: "result"
      <*> o .: "eventId"
      <*> o .: "event"
      <*> o .: "calledAt"
      <*> o .: "traceId"

-- | Outcome of 'record'.
--
-- __Description:__ 'Recorded' for a new document; 'AlreadyRecorded' with
-- the stored document when the call was logged before (a retry).
--
-- __Business Justification:__ Lets the service answer a retried call with
-- the original result and event.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data RecordResult
  = -- | The call was logged now.
    Recorded
  | -- | The call was logged earlier; the stored document.
    AlreadyRecorded CallRecord
  deriving stock (Eq, Show)

-- | Name of the call log database.
--
-- __Description:__ @successor_calls@, created by migration 0001.
--
-- __Business Justification:__ The call log of CLAUDE.md 3, step 7.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- >>> callsDatabase
-- "successor_calls"
callsDatabase :: Text
callsDatabase = "successor_calls"

-- | Name of the database recording applied migrations.
--
-- __Description:__ @successor_migrations@; one document per applied
-- migration file, keyed by its name without extension.
--
-- __Business Justification:__ Migrations run once (CLAUDE.md 6.1).
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- >>> migrationsDatabase
-- "successor_migrations"
migrationsDatabase :: Text
migrationsDatabase = "successor_migrations"

-- | Document identifier of a call.
--
-- __Description:__ @\<taskId\>:\<n\>@.
--
-- __Business Justification:__ Natural key of a call (see the module
-- documentation).
--
-- __Parameters:__
--
-- * @taskId@: the task.
-- * @n@: the argument.
--
-- __Returns:__ the identifier.
--
-- __Errors:__ None.
--
-- __Side Effects:__ None.
--
-- __Complexity:__ O(1).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__
--
-- >>> documentId "018f3c2e-7b1a-7c3d-9f00-0000000000aa" 3
-- "018f3c2e-7b1a-7c3d-9f00-0000000000aa:3"
--
-- __See Also:__ 'record'.
documentId :: Text -> Integer -> Text
documentId taskId n = taskId <> ":" <> Text.pack (show n)

-- | Creates the connection.
--
-- __Description:__ Builds an HTTP manager with a 250 ms response timeout.
-- No request is made.
--
-- __Business Justification:__ Startup of the service.
--
-- __Parameters:__
--
-- * @url@: base URL, e.g. @http://successor-db:5984@.
-- * @name@: CouchDB user.
-- * @secret@: its password.
--
-- __Returns:__ the connection.
--
-- __Errors:__ None.
--
-- __Side Effects:__ allocates the connection pool.
--
-- __Complexity:__ O(1).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @newCallLog "http://successor-db:5984" "successor" "change-me"@.
--
-- __See Also:__ 'migrate'.
newCallLog :: Text -> Text -> Text -> IO CallLog
newCallLog url name secret = do
  m <- newManager defaultManagerSettings {managerResponseTimeout = responseTimeoutMicro 250000}
  pure (CallLog m (Text.dropWhileEnd (== '/') url) (TE.encodeUtf8 name) (TE.encodeUtf8 secret))

-- | Sends one request (single attempt).
--
-- __Description:__ @method@ to @path@ (relative to the base URL) with an
-- optional JSON body; returns the status and the body.
--
-- __Business Justification:__ The only place that talks HTTP to CouchDB.
--
-- __Parameters:__
--
-- * @db@: the connection.
-- * @method@: HTTP method.
-- * @path@: path starting with @/@.
-- * @body@: JSON body, if any.
--
-- __Returns:__ status code and body.
--
-- __Errors:__ an @HttpException@ on a connection failure or timeout.
--
-- __Side Effects:__ one HTTP request.
--
-- __Complexity:__ O(size of the body).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @send db "GET" "/_up" Nothing@.
--
-- __See Also:__ 'attempt'.
send :: CallLog -> ByteString -> Text -> Maybe Value -> IO (Int, BL.ByteString)
send db method path body = do
  base <- parseRequest (Text.unpack (baseUrl db <> path))
  let req =
        applyBasicAuth (user db) (password db) $
          base
            { method = method,
              requestHeaders = [("Content-Type", "application/json"), ("Accept", "application/json")],
              requestBody = RequestBodyLBS (maybe "" Aeson.encode body)
            }
  resp <- httpLbs req (manager db)
  pure (statusCode (responseStatus resp), responseBody resp)

-- | Runs an action up to three times with jittered backoff.
--
-- __Description:__ Retries on any exception and on a result that the
-- predicate rejects (for example a 5xx status); waits 50 ms and 100 ms
-- (each ±50%) between attempts.
--
-- __Business Justification:__ Timeouts and retries with jitter on every
-- network call (CLAUDE.md 6.1).
--
-- __Parameters:__
--
-- * @what@: name of the operation, for the error.
-- * @ok@: accepts a result.
-- * @action@: the attempt.
--
-- __Returns:__ the first accepted result.
--
-- __Errors:__ 'CallLogError' after the third failed attempt.
--
-- __Side Effects:__ those of @action@; sleeps between attempts.
--
-- __Complexity:__ at most three attempts.
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @attempt "ping" ((== 200) . fst) (send db "GET" "/_up" Nothing)@.
--
-- __See Also:__ 'send'.
attempt :: Text -> ((Int, BL.ByteString) -> Bool) -> IO (Int, BL.ByteString) -> IO (Int, BL.ByteString)
attempt what ok action = go (1 :: Int)
  where
    go n = do
      result <- try action
      case result of
        Right r | ok r -> pure r
        _ | n >= 3 -> throwIO (CallLogError (what <> ": " <> describe result))
        _ -> do
          let base = 50000 * 2 ^ (n - 1) :: Int
          jitter <- randomRIO (base `div` 2, base + base `div` 2)
          threadDelay jitter
          go (n + 1)
    describe :: Either SomeException (Int, BL.ByteString) -> Text
    describe = \case
      Left e -> case fromException e of
        Just (HttpExceptionRequest _ content) -> Text.pack (show content)
        _ -> Text.pack (takeWhile (/= '\n') (show e))
      Right (status, _) -> "HTTP " <> Text.pack (show status)

-- | Checks that CouchDB is up and the call log exists.
--
-- __Description:__ One attempt of @GET /successor_calls@.
--
-- __Business Justification:__ The @database@ check of @GET /health@.
--
-- __Parameters:__
--
-- * @db@: the connection.
--
-- __Returns:__ 'True' on HTTP 200.
--
-- __Errors:__ None; failures return 'False'.
--
-- __Side Effects:__ one HTTP request.
--
-- __Complexity:__ O(1).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @ping db@.
--
-- __See Also:__ 'Successor.Api.application'.
ping :: CallLog -> IO Bool
ping db = do
  result <- try (send db "GET" ("/" <> callsDatabase) Nothing)
  pure $ case result of
    Right (200, _) -> True
    Right _ -> False
    Left (_ :: SomeException) -> False

-- | One operation of a migration file.
--
-- __Description:__ @{"createDatabase": name}@ or
-- @{"putDocument": {"database": name, "document": {...}}}@ (the document
-- carries its @_id@). Both are idempotent: an existing database (412) or
-- document (409) counts as done.
--
-- __Business Justification:__ The DDL of CouchDB.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data Operation
  = CreateDatabase Text
  | PutDocument Text Text Value

-- | Reads an operation; see 'Operation'.
instance FromJSON Operation where
  parseJSON = withObject "Operation" $ \o ->
    case (KeyMap.lookup "createDatabase" o, KeyMap.lookup "putDocument" o) of
      (Just name, _) -> CreateDatabase <$> parseJSON name
      (_, Just spec) -> flip (withObject "putDocument") spec $ \p -> do
        doc <- p .: "document"
        docId <- withObject "document" (.: "_id") doc
        PutDocument <$> p .: "database" <*> pure docId <*> pure doc
      _ -> fail "expected createDatabase or putDocument"

-- | A migration file.
--
-- __Description:__ @{"description": text, "operations": [...]}@.
--
-- __Business Justification:__ Versioned schema changes in
-- @migrations/@ (CLAUDE.md 6.1).
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data Migration = Migration Text [Operation]

-- | Reads a migration file; see 'Migration'.
instance FromJSON Migration where
  parseJSON = withObject "Migration" $ \o -> Migration <$> o .: "description" <*> o .: "operations"

-- | Path of a document, keeping @_design/@ unencoded.
--
-- __Description:__ @/\<database\>/\<id\>@ with the identifier
-- percent-encoded as a path segment (@:@ is allowed in a path and stays),
-- except the slash after @_design@, which CouchDB requires literally.
--
-- __Business Justification:__ Identifiers are safe in a URL whatever
-- they contain.
--
-- __Parameters:__
--
-- * @database@: the database.
-- * @docId@: the document identifier.
--
-- __Returns:__ the path.
--
-- __Errors:__ None.
--
-- __Side Effects:__ None.
--
-- __Complexity:__ O(n).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__
--
-- >>> documentPath "successor_calls" "t:3"
-- "/successor_calls/t:3"
-- >>> documentPath "successor_calls" "a b"
-- "/successor_calls/a%20b"
-- >>> documentPath "successor_calls" "_design/call_log"
-- "/successor_calls/_design/call_log"
--
-- __See Also:__ 'record'.
documentPath :: Text -> Text -> Text
documentPath database docId = case Text.stripPrefix "_design/" docId of
  Just name -> "/" <> database <> "/_design/" <> encode name
  Nothing -> "/" <> database <> "/" <> encode docId
  where
    encode = TE.decodeUtf8 . urlEncode False . TE.encodeUtf8

-- | Applies one operation.
--
-- __Description:__ See 'Operation'.
--
-- __Business Justification:__ Part of 'migrate'.
--
-- __Parameters:__
--
-- * @db@: the connection.
-- * @op@: the operation.
--
-- __Returns:__ nothing.
--
-- __Errors:__ 'CallLogError' on any other status.
--
-- __Side Effects:__ creates a database or a document.
--
-- __Complexity:__ O(1) requests.
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @apply db (CreateDatabase "successor_calls")@.
--
-- __See Also:__ 'migrate'.
apply :: CallLog -> Operation -> IO ()
apply db = \case
  CreateDatabase name ->
    void (attempt ("create database " <> name) (accept [201, 202, 412]) (send db "PUT" ("/" <> name) Nothing))
  PutDocument database docId doc ->
    void (attempt ("put " <> docId) (accept [201, 202, 409]) (send db "PUT" (documentPath database docId) (Just doc)))
  where
    accept codes (status, _) = status `elem` codes

-- | Applies the migrations not applied yet.
--
-- __Description:__ Creates @successor_migrations@ if needed, then applies
-- every @*.json@ file of @dir@ in name order whose record document is
-- missing, and writes its record (@appliedAt@, @description@).
--
-- __Business Justification:__ Migrations at startup (CLAUDE.md 6.1).
--
-- __Parameters:__
--
-- * @db@: the connection.
-- * @dir@: the migrations directory.
--
-- __Returns:__ the number of migrations applied now.
--
-- __Errors:__ 'CallLogError' on a CouchDB failure or an unreadable file;
-- an 'IOError' if @dir@ cannot be listed.
--
-- __Side Effects:__ creates databases and documents.
--
-- __Complexity:__ O(m) requests in the number of operations.
--
-- __Thread Safety:__ run once at startup.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @migrate db "/app/migrations"@ returns @1@ on a new database
-- and @0@ afterwards.
--
-- __See Also:__ services/successor/migrations/.
migrate :: CallLog -> FilePath -> IO Int
migrate db dir = do
  apply db (CreateDatabase migrationsDatabase)
  files <- sort . filter ((== ".json") . takeExtension) <$> listDirectory dir
  foldM step 0 files
  where
    step count file = do
      let name = Text.pack (dropExtension file)
      (status, _) <- attempt ("migration record " <> name) (\(s, _) -> s == 200 || s == 404) (send db "GET" (documentPath migrationsDatabase name) Nothing)
      if status == 200
        then pure count
        else do
          content <- BL.readFile (dir </> file)
          Migration description operations <- either (throwIO . CallLogError . (("migration " <> name <> ": ") <>) . Text.pack) pure (Aeson.eitherDecode content)
          forM_ operations (apply db)
          now <- formatTimestamp <$> nowMillis
          apply db (PutDocument migrationsDatabase name (object ["_id" .= name, "appliedAt" .= now, "description" .= description]))
          pure (count + 1)

-- | Logs one call.
--
-- __Description:__ Creates the document 'documentId' in @successor_calls@.
-- If it exists (HTTP 409, a retried call), reads and returns it.
--
-- __Business Justification:__ The call log of CLAUDE.md 3, step 7, and
-- the idempotency of retried calls.
--
-- __Parameters:__
--
-- * @db@: the connection.
-- * @rec@: the call.
--
-- __Returns:__ 'Recorded', or 'AlreadyRecorded' with the stored document.
--
-- __Errors:__ 'CallLogError' after three failed attempts or if the stored
-- document cannot be read.
--
-- __Side Effects:__ one or two HTTP requests; one new document.
--
-- __Complexity:__ O(1) requests.
--
-- __Thread Safety:__ safe; two concurrent writers of the same call get one
-- 'Recorded' and one 'AlreadyRecorded'.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @record db (CallRecord task 3 4 eventId event calledAt trace)@.
--
-- __See Also:__ 'Successor.Service.call'.
record :: CallLog -> CallRecord -> IO RecordResult
record db rec = do
  let path = documentPath callsDatabase (documentId (recTaskId rec) (recN rec))
      body = case toJSON rec of
        Aeson.Object o -> Aeson.Object (KeyMap.insert "_id" (Aeson.String (documentId (recTaskId rec) (recN rec))) o)
        other -> other
  (status, _) <- attempt "record call" (\(s, _) -> s `elem` [201, 202, 409]) (send db "PUT" path (Just body))
  if status /= 409
    then pure Recorded
    else do
      (_, stored) <- attempt "read call" ((== 200) . fst) (send db "GET" path Nothing)
      case Aeson.eitherDecode stored of
        Right r -> pure (AlreadyRecorded r)
        Left err -> throwIO (CallLogError ("read call: " <> Text.pack err))
