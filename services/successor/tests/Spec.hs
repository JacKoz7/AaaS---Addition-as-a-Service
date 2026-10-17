-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       successor
-- Module:          Main (tests/Spec.hs)
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         hspec suite of the successor service: arithmetic,
--                  identifiers, events, the call service with fake
--                  dependencies, the HTTP interface, configuration and,
--                  with COUCHDB_URL set, the CouchDB call log.
-- Related Docs:    services/successor/README.md (Running and testing),
--                  ADR-0016

-- | Unit and integration tests of the successor.
--
-- __Description:__ The pure modules and the HTTP application are tested
-- with fake dependencies. When @COUCHDB_URL@ is set (the Makefile starts a
-- throw-away CouchDB container for that), the call log is tested against
-- a real database. When @PRODUCED_DIR@ is set, every event the fake
-- publisher receives is written there; the Dockerfile test stage then
-- validates the files against their JSON Schema.
--
-- __Business Justification:__ @make test-successor@ (CLAUDE.md 6.3).
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
module Main (main) where

import Control.Monad (forM_)
import Data.Aeson (Value (..), decode, encode, object, (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.CaseInsensitive qualified as CI
import Data.IORef (IORef, atomicModifyIORef', modifyIORef', newIORef, readIORef)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TE
import Network.HTTP.Types (hContentType, methodGet, methodPost, status200)
import Network.Wai (Request (..))
import Network.Wai.Test
  ( SRequest (..),
    SResponse (..),
    defaultRequest,
    request,
    runSession,
    setPath,
    srequest,
  )
import Successor.Api (Env (..), application)
import Successor.CallLog
  ( CallRecord (..),
    RecordResult (..),
    documentId,
    migrate,
    newCallLog,
    ping,
    record,
  )
import Successor.Config (Config (..), loadConfig)
import Successor.Core (NextError (..), maxArgument, next)
import Successor.Event (successorCalled)
import Successor.Identifiers (formatTimestamp, isUuid, newUuidV7, uuidV7FromParts)
import Successor.Log (Level (..), newLogger, renderLine)
import Successor.Metrics (Metrics, newMetrics, render)
import Successor.Service (CallRequest (..), Deps (..), Failure (..), Outcome (..), call)
import Successor.Trace (TraceContext (..), childSpan, parseTraceparent, renderTraceparent)
import System.Directory (createDirectoryIfMissing)
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import Test.Hspec

-- | A valid sampleTask identifier used throughout the tests.
sampleTask :: Text
sampleTask = "018f3c2e-7b1a-7c3d-9f00-0000000000aa"

-- | The parent trace of the CLAUDE.md example.
parentTrace :: TraceContext
parentTrace = TraceContext "4bf92f3577b34da6a3ce929d0e0e4736" "00f067aa0ba902b7" "01"

-- | Fake dependencies: an in-memory call log and a recording publisher.
--
-- __Description:__ Returns the 'Deps', the published @(key, value)@
-- pairs (newest first) and a switch that makes the next publications fail.
fakeDeps :: IO (Deps, IORef [(BS.ByteString, BS.ByteString)], IORef Bool)
fakeDeps = do
  store <- newIORef (Map.empty :: Map.Map Text CallRecord)
  sent <- newIORef []
  failing <- newIORef False
  produced <- lookupEnv "PRODUCED_DIR"
  let recordFake rec = atomicModifyIORef' store $ \m ->
        let key = documentId (recTaskId rec) (recN rec)
         in case Map.lookup key m of
              Just stored -> (m, AlreadyRecorded stored)
              Nothing -> (Map.insert key rec m, Recorded)
      publishFake key value = do
        broken <- readIORef failing
        if broken
          then pure (Left "broker down")
          else do
            modifyIORef' sent ((key, value) :)
            forM_ produced $ \dir -> do
              createDirectoryIfMissing True dir
              name <- newUuidV7
              BS.writeFile (dir </> Text.unpack name <> ".json") value
            pure (Right ())
  pure (Deps recordFake publishFake (pure 1792152000000) newUuidV7, sent, failing)

-- | The application with fake dependencies and the shared metrics.
testEnv :: Metrics -> Deps -> [(Text, IO Bool)] -> IO Env
testEnv metrics deps checks = do
  logger <- newLogger "successor" Fatal
  pure (Env deps logger metrics checks render)

-- | POSTs a JSON body to @/v1/next@.
postNext :: Env -> [(BS.ByteString, BS.ByteString)] -> BL.ByteString -> IO SResponse
postNext env headers body =
  runSession
    (srequest (SRequest (setPath defaultRequest {requestMethod = methodPost, requestHeaders = (hContentType, "application/json") : map (first CI.mk) headers} "/v1/next") body))
    (application env)

-- | GETs a path.
getPath :: Env -> BS.ByteString -> IO SResponse
getPath env path = runSession (request (setPath defaultRequest {requestMethod = methodGet} path)) (application env)

-- | Reads a JSON field of a response body.
field :: Text -> SResponse -> Maybe Value
field name resp = case decode (simpleBody resp) of
  Just (Object o) -> KeyMap.lookup (Key.fromText name) o
  _ -> Nothing

-- | Runs every spec.
main :: IO ()
main = do
  metrics <- newMetrics "test"
  couch <- lookupEnv "COUCHDB_URL"
  migrations <- fromMaybe "migrations" <$> lookupEnv "MIGRATIONS_DIR"
  hspec $ do
    describe "Core.next" $ do
      it "adds one inside the domain" $ do
        next 0 `shouldBe` Right 1
        next 199 `shouldBe` Right 200
        next maxArgument `shouldBe` Right 199998
      it "rejects arguments outside the domain" $ do
        next (-1) `shouldBe` Left (Negative (-1))
        next 199998 `shouldBe` Left (AboveRange 199998)

    describe "Identifiers" $ do
      it "lays out a UUIDv7" $ do
        uuidV7FromParts 0x018f3c2e7b1a (BS.replicate 10 0) `shouldBe` Just "018f3c2e-7b1a-7000-8000-000000000000"
        uuidV7FromParts 0x018f3c2e7b1a (BS.replicate 10 255) `shouldBe` Just "018f3c2e-7b1a-7fff-bfff-ffffffffffff"
        uuidV7FromParts 0 "short" `shouldBe` Nothing
      it "generates unique version 7 identifiers" $ do
        a <- newUuidV7
        b <- newUuidV7
        a `shouldNotBe` b
        isUuid a `shouldBe` True
        Text.index a 14 `shouldBe` '7'
      it "formats timestamps" $ do
        formatTimestamp 1792152000000 `shouldBe` "2026-10-16T12:00:00.000Z"
        formatTimestamp 1835481599999 `shouldBe` "2028-02-29T23:59:59.999Z"

    describe "Trace" $ do
      it "parses and renders traceparent" $ do
        let value = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        (renderTraceparent <$> parseTraceparent value) `shouldBe` Just value
        forM_ ["", "01-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01", "00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01", "00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01"] $ \v ->
          parseTraceparent v `shouldBe` Nothing
      it "continues the parent trace with a new span" $ do
        child <- childSpan (Just parentTrace)
        traceId child `shouldBe` traceId parentTrace
        spanId child `shouldNotBe` spanId parentTrace
        root <- childSpan Nothing
        parseTraceparent (renderTraceparent root) `shouldBe` Just root

    describe "Event" $
      it "serializes the envelope in specification order" $ do
        let bytes = successorCalled "018f3c2e-7b1a-7c3d-9f00-000000000020" 1792152001250 sampleTask parentTrace 3 4
        bytes
          `shouldBe` TE.encodeUtf8
            "{\"eventId\":\"018f3c2e-7b1a-7c3d-9f00-000000000020\",\"type\":\"aaas.successor.called\",\"version\":1,\"occurredAt\":\"2026-10-16T12:00:01.250Z\",\"producer\":\"successor\",\"taskId\":\"018f3c2e-7b1a-7c3d-9f00-0000000000aa\",\"traceparent\":\"00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01\",\"payload\":{\"n\":3,\"result\":4}}"

    describe "Service.call" $ do
      it "computes, logs and publishes" $ do
        (deps, sent, _) <- fakeDeps
        call deps (CallRequest 199 sampleTask parentTrace) `shouldReturn` Right (Computed 200)
        published <- readIORef sent
        map fst published `shouldBe` [TE.encodeUtf8 sampleTask]
      it "answers a retried call from the log with the identical event" $ do
        (deps, sent, _) <- fakeDeps
        _ <- call deps (CallRequest 41 sampleTask parentTrace)
        call deps (CallRequest 41 sampleTask parentTrace) `shouldReturn` Right (Replayed 42)
        published <- readIORef sent
        length published `shouldBe` 2
        case published of
          [(_, retried), (_, original)] -> retried `shouldBe` original
          _ -> expectationFailure "two messages expected"
      it "does not log or publish an invalid argument" $ do
        (deps, sent, _) <- fakeDeps
        call deps (CallRequest 199998 sampleTask parentTrace) `shouldReturn` Left (InvalidArgument (AboveRange 199998))
        readIORef sent `shouldReturn` []
      it "reports a publication failure, and a retry publishes the stored event" $ do
        (deps, sent, failing) <- fakeDeps
        modifyIORef' failing (const True)
        call deps (CallRequest 7 sampleTask parentTrace) `shouldReturn` Left (DependencyFailed "kafka" "broker down")
        modifyIORef' failing (const False)
        call deps (CallRequest 7 sampleTask parentTrace) `shouldReturn` Right (Replayed 8)
        (length <$> readIORef sent) `shouldReturn` 1
      it "reports a call log failure" $ do
        (deps, _, _) <- fakeDeps
        let broken = deps {recordCall = \_ -> ioError (userError "couchdb down")}
        result <- call broken (CallRequest 1 sampleTask parentTrace)
        case result of
          Left (DependencyFailed "couchdb" _) -> pure ()
          other -> expectationFailure (show other)

    describe "Api" $ do
      it "answers POST /v1/next with n + 1 and continues the trace" $ do
        (deps, sent, _) <- fakeDeps
        env <- testEnv metrics deps []
        resp <- postNext env [("traceparent", TE.encodeUtf8 (renderTraceparent parentTrace))] (encode (object ["n" .= (2 :: Int), "taskId" .= sampleTask]))
        simpleStatus resp `shouldBe` status200
        field "n" resp `shouldBe` Just (Number 3)
        published <- readIORef sent
        case published of
          [(_, value)] -> BS.isInfixOf (TE.encodeUtf8 (traceId parentTrace)) value `shouldBe` True
          _ -> expectationFailure "one message expected"
      it "refuses malformed requests with problems" $ do
        (deps, _, _) <- fakeDeps
        env <- testEnv metrics deps []
        let cases =
              [ ("not json", 400),
                ("{\"n\":2.5,\"taskId\":\"018f3c2e-7b1a-7c3d-9f00-0000000000aa\"}", 400),
                ("{\"n\":2,\"taskId\":\"X\"}", 422),
                ("{\"n\":199998,\"taskId\":\"018f3c2e-7b1a-7c3d-9f00-0000000000aa\"}", 422),
                ("{\"n\":-1,\"taskId\":\"018f3c2e-7b1a-7c3d-9f00-0000000000aa\"}", 422)
              ]
        forM_ cases $ \(body, code) -> do
          resp <- postNext env [] body
          lookup hContentType (simpleHeaders resp) `shouldBe` Just "application/problem+json"
          field "status" resp `shouldBe` Just (Number code)
      it "maps a dependency failure to 503" $ do
        (deps, _, failing) <- fakeDeps
        modifyIORef' failing (const True)
        env <- testEnv metrics deps []
        resp <- postNext env [] (encode (object ["n" .= (2 :: Int), "taskId" .= sampleTask]))
        field "status" resp `shouldBe` Just (Number 503)
      it "reports health and metrics" $ do
        (deps, _, _) <- fakeDeps
        ok <- testEnv metrics deps [("database", pure True), ("broker", pure True)]
        bad <- testEnv metrics deps [("database", pure True), ("broker", pure False)]
        healthy <- getPath ok "/health"
        simpleBody healthy `shouldBe` "{\"checks\":{\"broker\":\"ok\",\"database\":\"ok\"},\"status\":\"ok\"}"
        unhealthy <- getPath bad "/health"
        field "status" unhealthy `shouldBe` Just (String "error")
        m <- getPath ok "/metrics"
        BS.isInfixOf "successor_calls_total" (BL.toStrict (simpleBody m)) `shouldBe` True
        missing <- getPath ok "/nope"
        field "status" missing `shouldBe` Just (Number 404)
        wrong <- runSession (request (setPath defaultRequest {requestMethod = methodPost} "/health")) (application ok)
        field "status" wrong `shouldBe` Just (Number 405)

    describe "Config" $ do
      let env pairs name = lookup name pairs
      it "reads defaults and requires the password" $ do
        (brokers <$> loadConfig (env [("SUCCESSOR_DB_PASSWORD", "x")])) `shouldBe` Right "redpanda:9092"
        (httpPort <$> loadConfig (env [("SUCCESSOR_DB_PASSWORD", "x")])) `shouldBe` Right 8080
        either (const True) (const False) (loadConfig (env [])) `shouldBe` True
      it "rejects invalid values"
        $ forM_
          [ [("AAAS_BOOTSTRAP", "platform")],
            [("AAAS_HTTP_PORT", "http")],
            [("AAAS_LOG_LEVEL", "loud")],
            [("AAAS_KAFKA_LOG_LEVEL", "9")]
          ]
        $ \pairs -> either (const True) (const False) (loadConfig (env (("SUCCESSOR_DB_PASSWORD", "x") : pairs))) `shouldBe` True

    describe "Log" $
      it "renders the fields of CLAUDE.md 6.1 in order" $ do
        let line = renderLine "t" "successor" Warn (Just sampleTask) (Just parentTrace) "m" [("n", Number 1)]
        line `shouldBe` "{\"ts\":\"t\",\"level\":\"warn\",\"service\":\"successor\",\"msg\":\"m\",\"taskId\":\"018f3c2e-7b1a-7c3d-9f00-0000000000aa\",\"traceId\":\"4bf92f3577b34da6a3ce929d0e0e4736\",\"spanId\":\"00f067aa0ba902b7\",\"n\":1}"

    describe "CallLog (CouchDB, needs COUCHDB_URL)" $
      case couch of
        Nothing -> it "is skipped without COUCHDB_URL" pending
        Just url -> do
          it "migrates once and logs a call once" $ do
            db <- newCallLog (Text.pack url) "successor" "change-me"
            applied <- migrate db migrations
            applied `shouldSatisfy` (>= 0)
            migrate db migrations `shouldReturn` 0
            ping db `shouldReturn` True
            taskId <- newUuidV7
            let rec = CallRecord taskId 3 4 "018f3c2e-7b1a-7c3d-9f00-000000000020" "{}" "2026-10-16T12:00:00.000Z" (traceId parentTrace)
            record db rec `shouldReturn` Recorded
            record db rec {recEventId = "other"} `shouldReturn` AlreadyRecorded rec
          it "serves calls end to end against CouchDB" $ do
            db <- newCallLog (Text.pack url) "successor" "change-me"
            (deps, sent, _) <- fakeDeps
            let real = deps {recordCall = record db}
            taskId <- newUuidV7
            call real (CallRequest 99999 taskId parentTrace) `shouldReturn` Right (Computed 100000)
            call real (CallRequest 99999 taskId parentTrace) `shouldReturn` Right (Replayed 100000)
            published <- readIORef sent
            case published of
              [(_, a), (_, b)] -> a `shouldBe` b
              _ -> expectationFailure "two messages expected"
