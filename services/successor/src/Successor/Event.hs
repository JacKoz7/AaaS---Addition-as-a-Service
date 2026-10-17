-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       successor
-- Module:          Successor.Event
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Builds the aaas.successor.called.v1 event of one call.
-- Related Docs:    contracts/events/aaas.successor.called.v1.schema.json,
--                  CLAUDE.md 4.2, ADR-0013, ADR-0016

-- | The event published for every successor call.
--
-- __Description:__ The envelope of CLAUDE.md 4.2 with the payload
-- @{n, result}@, serialized with its fields in the order of the
-- specification.
--
-- __Business Justification:__ Audit trail of the Peano arithmetic: an
-- addition @a + b@ leaves @b@ events on @aaas.successor.called.v1@.
--
-- __Thread Safety:__ pure; safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
module Successor.Event
  ( topic,
    successorCalled,
  )
where

import Data.Aeson ((.=))
import Data.Aeson.Encoding (encodingToLazyByteString, pair, pairs)
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Successor.Identifiers (formatTimestamp)
import Successor.Trace (TraceContext, renderTraceparent)

-- | Topic of the event.
--
-- __Description:__ @aaas.successor.called.v1@, keyed by @taskId@.
--
-- __Business Justification:__ CLAUDE.md 4.2, topic table.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- >>> topic
-- "aaas.successor.called.v1"
topic :: Text
topic = "aaas.successor.called.v1"

-- | Serializes the event of one call.
--
-- __Description:__ @eventId@, @type@, @version@, @occurredAt@, @producer@,
-- @taskId@, @traceparent@ and @payload {n, result}@, in this order.
--
-- __Business Justification:__ The exact bytes stored in the call log and
-- published, so that a retried call republishes the identical event.
--
-- __Parameters:__
--
-- * @eventId@: a new UUIDv7.
-- * @millis@: the event time, Unix milliseconds.
-- * @taskId@: the task of the call.
-- * @trace@: the context of the serving span.
-- * @n@: the argument, @0..199997@.
-- * @result@: @n + 1@.
--
-- __Returns:__ the JSON bytes.
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
-- >>> import Successor.Trace (TraceContext (..))
-- >>> successorCalled "e" 0 "t" (TraceContext "a" "b" "01") 3 4
-- "{\"eventId\":\"e\",\"type\":\"aaas.successor.called\",\"version\":1,\"occurredAt\":\"1970-01-01T00:00:00.000Z\",\"producer\":\"successor\",\"taskId\":\"t\",\"traceparent\":\"00-a-b-01\",\"payload\":{\"n\":3,\"result\":4}}"
--
-- __See Also:__ 'Successor.Service.call'.
successorCalled :: Text -> Integer -> Text -> TraceContext -> Integer -> Integer -> ByteString
successorCalled eventId millis taskId trace n result =
  BL.toStrict . encodingToLazyByteString . pairs $
    mconcat
      [ "eventId" .= eventId,
        "type" .= ("aaas.successor.called" :: Text),
        "version" .= (1 :: Int),
        "occurredAt" .= formatTimestamp millis,
        "producer" .= ("successor" :: Text),
        "taskId" .= taskId,
        "traceparent" .= renderTraceparent trace,
        pair "payload" (pairs ("n" .= n <> "result" .= result))
      ]
