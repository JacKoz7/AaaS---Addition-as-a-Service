-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       successor
-- Module:          Successor.Service
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Serves one successor call: computes n + 1, logs the call
--                  in CouchDB and publishes aaas.successor.called.v1.
-- Related Docs:    services/successor/README.md, CLAUDE.md 3 (step 7) and
--                  4.3, ADR-0016

-- | One successor call, end to end.
--
-- __Description:__ 'call' runs, in order:
--
-- 1. 'Successor.Core.next' (an argument outside @0..199997@ is rejected,
--    nothing is logged);
-- 2. the call log ('Successor.CallLog.record'): a new document with the
--    serialized event, or, for a retried call, the stored document;
-- 3. the publication of the event (the new one, or the stored one again,
--    so its @eventId@ never changes).
--
-- The answer is sent only after both side effects succeeded. Dependencies
-- are passed as functions ('Deps') so that tests run without CouchDB and
-- Kafka.
--
-- __Business Justification:__ Step 7 of the request flow (CLAUDE.md 3):
-- every successor call is computed, logged and announced.
--
-- __Thread Safety:__ safe; concurrent calls share no state here.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
module Successor.Service
  ( Deps (..),
    CallRequest (..),
    Outcome (..),
    Failure (..),
    call,
  )
where

import Control.Exception (SomeException, try)
import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TE
import Successor.CallLog (CallRecord (..), RecordResult (..))
import Successor.Core (NextError, next)
import Successor.Event (successorCalled)
import Successor.Identifiers (formatTimestamp)
import Successor.Trace (TraceContext (..))

-- | The side effects 'call' needs.
--
-- __Description:__ In production: the CouchDB call log, the Kafka
-- publisher (key, value), the wall clock and the UUIDv7 generator.
--
-- __Business Justification:__ Testability without infrastructure.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data Deps = Deps
  { -- | Logs a call ('Successor.CallLog.record').
    recordCall :: CallRecord -> IO RecordResult,
    -- | Publishes an event and waits for the acknowledgement.
    publishEvent :: ByteString -> ByteString -> IO (Either Text ()),
    -- | Current time, Unix milliseconds.
    clock :: IO Integer,
    -- | A new UUIDv7.
    freshId :: IO Text
  }

-- | A validated request.
--
-- __Description:__ The argument, its task and the serving span.
--
-- __Business Justification:__ Input of 'call', built by the API layer.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data CallRequest = CallRequest
  { -- | The argument @n@.
    argument :: Integer,
    -- | The task (lowercase UUID).
    task :: Text,
    -- | The context of the serving span.
    servingSpan :: TraceContext
  }
  deriving stock (Eq, Show)

-- | A successful call.
--
-- __Description:__ 'Computed' for a first call, 'Replayed' for a retried
-- call answered from the call log; both carry @n + 1@.
--
-- __Business Justification:__ Metrics distinguish retries.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data Outcome
  = -- | First call: logged and published now.
    Computed Integer
  | -- | Retried call: stored result, stored event published again.
    Replayed Integer
  deriving stock (Eq, Show)

-- | A failed call.
--
-- __Description:__ 'InvalidArgument' for an argument outside the domain;
-- 'DependencyFailed' with the dependency (@couchdb@ or @kafka@) and the
-- cause.
--
-- __Business Justification:__ Mapped to 422 and 503 problems.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data Failure
  = -- | The argument is outside @0..199997@.
    InvalidArgument NextError
  | -- | A dependency failed after its retries.
    DependencyFailed Text Text
  deriving stock (Eq, Show)

-- | Serves one call.
--
-- __Description:__ See the module documentation.
--
-- __Business Justification:__ The core use case of the service.
--
-- __Parameters:__
--
-- * @deps@: the side effects.
-- * @req@: the validated request.
--
-- __Returns:__ the 'Outcome', or the 'Failure'.
--
-- __Errors:__ 'InvalidArgument' outside the domain; 'DependencyFailed'
-- if the call log or the publication fails, or if a stored call has a
-- different result (a corrupted log).
--
-- __Side Effects:__ at most one new document; one Kafka message.
--
-- __Complexity:__ O(1) plus two round trips.
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @call deps (CallRequest 199 task span)@ returns
-- @Right (Computed 200)@, and @Right (Replayed 200)@ when repeated.
--
-- __See Also:__ 'Successor.Api.application', 'Successor.Core.next'.
call :: Deps -> CallRequest -> IO (Either Failure Outcome)
call deps req = case next (argument req) of
  Left err -> pure (Left (InvalidArgument err))
  Right result -> do
    millis <- clock deps
    eventId <- freshId deps
    let event = successorCalled eventId millis (task req) (servingSpan req) (argument req) result
        rec =
          CallRecord
            { recTaskId = task req,
              recN = argument req,
              recResult = result,
              recEventId = eventId,
              recEvent = TE.decodeUtf8 event,
              recCalledAt = formatTimestamp millis,
              recTraceId = traceId (servingSpan req)
            }
    logged <- try (recordCall deps rec)
    case logged of
      Left (e :: SomeException) -> pure (Left (DependencyFailed "couchdb" (firstLine e)))
      Right Recorded -> announce event (Computed result)
      Right (AlreadyRecorded stored)
        | recResult stored /= result ->
            pure (Left (DependencyFailed "couchdb" "stored call has a different result"))
        | otherwise -> announce (TE.encodeUtf8 (recEvent stored)) (Replayed result)
  where
    announce event outcome = do
      sent <- publishEvent deps (TE.encodeUtf8 (task req)) event
      pure $ case sent of
        Left err -> Left (DependencyFailed "kafka" err)
        Right () -> Right outcome
    firstLine e = Text.pack (takeWhile (/= '\n') (show e))
