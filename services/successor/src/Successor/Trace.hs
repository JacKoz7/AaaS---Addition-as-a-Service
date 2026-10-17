-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       successor
-- Module:          Successor.Trace
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Reads the W3C traceparent of a request and derives the
--                  context of the span that serves it.
-- Related Docs:    W3C Trace Context, CLAUDE.md 6.1, ADR-0013, ADR-0016

-- | W3C Trace Context, version @00@.
--
-- __Description:__ @00-\<32 hex trace-id\>-\<16 hex parent-id\>-\<2 hex flags\>@,
-- lowercase, non-zero identifiers. Serving a request is one span: same
-- trace and flags as the caller, a new span identifier. Without a valid
-- header a new sampled trace starts.
--
-- __Business Justification:__ One trace per addition (CLAUDE.md 6.1,
-- P7.2): the @traceparent@ of the published event and the @traceId@ and
-- @spanId@ of the log lines come from here.
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
module Successor.Trace
  ( TraceContext (..),
    parseTraceparent,
    renderTraceparent,
    childSpan,
  )
where

import Data.Char (isDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Successor.Identifiers (hex, randomBytes)

-- | A parsed traceparent.
--
-- __Description:__ lowercase hexadecimal trace identifier (32), span
-- identifier (16) and flags (2).
--
-- __Business Justification:__ Fields of logs and events.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data TraceContext = TraceContext
  { -- | Trace identifier, 32 lowercase hex characters.
    traceId :: Text,
    -- | Span identifier, 16 lowercase hex characters.
    spanId :: Text,
    -- | Trace flags, 2 lowercase hex characters.
    flags :: Text
  }
  deriving stock (Eq, Show)

-- | Parses a traceparent value.
--
-- __Description:__ Version @00@ only, lowercase, non-zero identifiers, as
-- the envelope schema requires.
--
-- __Business Justification:__ The caller's trace is continued only if it
-- is valid.
--
-- __Parameters:__
--
-- * @value@: the header value.
--
-- __Returns:__ the context, or 'Nothing' if invalid.
--
-- __Errors:__ 'Nothing' for any malformed value.
--
-- __Side Effects:__ None.
--
-- __Complexity:__ O(1) (fixed length).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__
--
-- >>> parseTraceparent "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
-- Just (TraceContext {traceId = "4bf92f3577b34da6a3ce929d0e0e4736", spanId = "00f067aa0ba902b7", flags = "01"})
-- >>> parseTraceparent "00-00000000000000000000000000000000-00f067aa0ba902b7-01"
-- Nothing
--
-- __See Also:__ 'renderTraceparent'.
parseTraceparent :: Text -> Maybe TraceContext
parseTraceparent value = case Text.splitOn "-" value of
  ["00", t, s, f]
    | lowerHex 32 t && lowerHex 16 s && lowerHex 2 f && not (zero t) && not (zero s) ->
        Just (TraceContext t s f)
  _ -> Nothing
  where
    lowerHex n x = Text.length x == n && Text.all (\c -> isDigit c || (c >= 'a' && c <= 'f')) x
    zero = Text.all (== '0')

-- | Renders a context as a traceparent value.
--
-- __Description:__ @00-\<traceId\>-\<spanId\>-\<flags\>@.
--
-- __Business Justification:__ The @traceparent@ of published events.
--
-- __Parameters:__
--
-- * @ctx@: the context.
--
-- __Returns:__ the traceparent text.
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
-- >>> renderTraceparent (TraceContext (Text.replicate 32 "a") (Text.replicate 16 "b") "01")
-- "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-01"
--
-- __See Also:__ 'parseTraceparent'.
renderTraceparent :: TraceContext -> Text
renderTraceparent ctx = Text.intercalate "-" ["00", traceId ctx, spanId ctx, flags ctx]

-- | Derives the context of the span serving a request.
--
-- __Description:__ With a parent, keeps its trace and flags and draws a new
-- non-zero span identifier; without one, starts a sampled trace.
--
-- __Business Justification:__ Continues the trace of the addition.
--
-- __Parameters:__
--
-- * @parent@: the caller's context, if valid.
--
-- __Returns:__ the context of the serving span.
--
-- __Errors:__ an 'IOError' if the random source cannot be read.
--
-- __Side Effects:__ reads the random source.
--
-- __Complexity:__ O(1) expected.
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @traceId \<$\> childSpan p@ equals @traceId \<$\> p@ for a
-- valid parent @p@.
--
-- __See Also:__ 'parseTraceparent'.
childSpan :: Maybe TraceContext -> IO TraceContext
childSpan parent = case parent of
  Just p -> (\s -> p {spanId = s}) <$> nonZero 8
  Nothing -> TraceContext <$> nonZero 16 <*> nonZero 8 <*> pure "01"
  where
    nonZero n = do
      h <- hex <$> randomBytes n
      if Text.all (== '0') h then nonZero n else pure h
