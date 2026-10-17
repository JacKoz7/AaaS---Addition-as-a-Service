-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       successor
-- Module:          Successor.Log
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Structured JSON log lines on stdout with the fields of
--                  CLAUDE.md 6.1.
-- Related Docs:    CLAUDE.md 6.1, ADR-0016

-- | Structured logging.
--
-- __Description:__ One JSON object per line with @ts@, @level@, @service@,
-- @msg@, @taskId@, @traceId@ and @spanId@ (null when unknown), then extra
-- fields, in this order. Lines below the minimum level are dropped. A
-- lock keeps lines of concurrent requests from interleaving.
--
-- __Business Justification:__ The same log fields in all 28 languages, so
-- Loki (P7.1) can follow a task across services.
--
-- __Thread Safety:__ safe (one lock per logger).
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
module Successor.Log
  ( Level (..),
    parseLevel,
    levelName,
    Logger (..),
    newLogger,
    renderLine,
    logMsg,
  )
where

import Control.Concurrent.MVar (MVar, newMVar, withMVar)
import Data.Aeson (Value (Null, String), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Encoding (encodingToLazyByteString, pair, pairs)
import Data.Aeson.Key qualified as Key
import Data.ByteString.Lazy qualified as BL
import Data.ByteString.Lazy.Char8 qualified as BLC
import Data.Text (Text)
import Data.Text qualified as Text
import Successor.Identifiers (formatTimestamp, nowMillis)
import Successor.Trace (TraceContext (..))
import System.IO (hFlush, stdout)

-- | Severity of a log line, from 'Debug' (lowest) to 'Fatal'.
--
-- __Description:__ The derived 'Ord' instance orders the levels.
--
-- __Business Justification:__ The level vocabulary shared by every AaaS
-- service.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data Level
  = -- | Diagnostic detail, off by default.
    Debug
  | -- | Normal operation.
    Info
  | -- | Something unexpected that the service handled.
    Warn
  | -- | A failed operation.
    Error
  | -- | The process cannot continue.
    Fatal
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | Reads a level name, case-insensitively.
--
-- __Description:__ Inverse of 'levelName'.
--
-- __Business Justification:__ The @AAAS_LOG_LEVEL@ variable.
--
-- __Parameters:__
--
-- * @t@: a level name.
--
-- __Returns:__ the level, if known.
--
-- __Errors:__ 'Nothing' for an unknown name.
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
-- >>> parseLevel "WARN"
-- Just Warn
--
-- __See Also:__ 'levelName'.
parseLevel :: Text -> Maybe Level
parseLevel t = lookup (Text.toLower t) [(levelName l, l) | l <- [minBound .. maxBound]]

-- | Name of a level in log lines.
--
-- __Description:__ @debug@, @info@, @warn@, @error@, @fatal@.
--
-- __Business Justification:__ The shared level vocabulary.
--
-- __Parameters:__
--
-- * @level@: a level.
--
-- __Returns:__ its name.
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
-- >>> levelName Warn
-- "warn"
--
-- __See Also:__ 'parseLevel'.
levelName :: Level -> Text
levelName = \case
  Debug -> "debug"
  Info -> "info"
  Warn -> "warn"
  Error -> "error"
  Fatal -> "fatal"

-- | A logger: service name, minimum level, output and its lock.
--
-- __Description:__ Built by 'newLogger'; tests supply their own 'sink'.
--
-- __Business Justification:__ Passed explicitly instead of global state.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data Logger = Logger
  { -- | The @service@ field of every line.
    serviceName :: Text,
    -- | Lines below this level are dropped.
    minLevel :: Level,
    -- | Writes one complete line.
    sink :: BL.ByteString -> IO (),
    -- | Serializes writes.
    lock :: MVar ()
  }

-- | Creates a logger writing to stdout.
--
-- __Description:__ Each line is followed by a newline and a flush.
--
-- __Business Justification:__ Logs go to stdout (CLAUDE.md 6.1).
--
-- __Parameters:__
--
-- * @name@: the service name.
-- * @level@: the minimum level.
--
-- __Returns:__ the logger.
--
-- __Errors:__ None.
--
-- __Side Effects:__ allocates the lock.
--
-- __Complexity:__ O(1).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @newLogger "successor" Info@.
--
-- __See Also:__ 'logMsg'.
newLogger :: Text -> Level -> IO Logger
newLogger name level = do
  l <- newMVar ()
  pure (Logger name level (\line -> BLC.putStrLn line >> hFlush stdout) l)

-- | Renders one log line.
--
-- __Description:__ The fixed fields in the order of CLAUDE.md 6.1, then the
-- extra fields.
--
-- __Business Justification:__ Separated from 'logMsg' for tests.
--
-- __Parameters:__
--
-- * @ts@: the timestamp text.
-- * @name@: the service name.
-- * @level@: the severity.
-- * @taskId@: the task, if any.
-- * @trace@: the trace context, if any.
-- * @msg@: the message.
-- * @extra@: extra fields.
--
-- __Returns:__ the JSON line without a newline.
--
-- __Errors:__ None.
--
-- __Side Effects:__ None.
--
-- __Complexity:__ O(size of the line).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__
--
-- >>> renderLine "t" "successor" Info Nothing Nothing "started" []
-- "{\"ts\":\"t\",\"level\":\"info\",\"service\":\"successor\",\"msg\":\"started\",\"taskId\":null,\"traceId\":null,\"spanId\":null}"
--
-- __See Also:__ 'logMsg'.
renderLine :: Text -> Text -> Level -> Maybe Text -> Maybe TraceContext -> Text -> [(Text, Value)] -> BL.ByteString
renderLine ts name level task trace msg extra =
  encodingToLazyByteString . pairs . mconcat $
    [ "ts" .= ts,
      "level" .= levelName level,
      "service" .= name,
      "msg" .= msg,
      "taskId" .= maybe Null String task,
      "traceId" .= maybe Null (String . traceId) trace,
      "spanId" .= maybe Null (String . spanId) trace
    ]
      ++ [pair (Key.fromText k) (Aeson.toEncoding v) | (k, v) <- extra]

-- | Writes one log line if its level is enabled.
--
-- __Description:__ Timestamps the line and writes it under the lock.
--
-- __Business Justification:__ The single logging entry point.
--
-- __Parameters:__
--
-- * @logger@: the logger.
-- * @level@: the severity.
-- * @taskId@: the task, if any.
-- * @trace@: the trace context, if any.
-- * @msg@: the message.
-- * @extra@: extra fields.
--
-- __Returns:__ nothing.
--
-- __Errors:__ None.
--
-- __Side Effects:__ writes to the sink.
--
-- __Complexity:__ O(size of the line).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @logMsg logger Info Nothing Nothing "started" []@.
--
-- __See Also:__ 'renderLine'.
logMsg :: Logger -> Level -> Maybe Text -> Maybe TraceContext -> Text -> [(Text, Value)] -> IO ()
logMsg logger level task trace msg extra
  | level < minLevel logger = pure ()
  | otherwise = do
      ts <- formatTimestamp <$> nowMillis
      withMVar (lock logger) $ \_ ->
        sink logger (renderLine ts (serviceName logger) level task trace msg extra)
