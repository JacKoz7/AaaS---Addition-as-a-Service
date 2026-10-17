-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       successor
-- Module:          Successor.Publisher
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Kafka producer of aaas.successor.called.v1 that waits for
--                  the broker's acknowledgement of every message.
-- Related Docs:    CLAUDE.md 4.2 and 6.1, ADR-0011, ADR-0016

-- | Kafka publication through hw-kafka-client (librdkafka).
--
-- __Description:__ An idempotent producer with @acks=all@ and a 1 s
-- message timeout. hw-kafka-client fires delivery reports only while
-- librdkafka is polled, and its producer has no polling thread of its own,
-- so 'newPublisher' starts one: it calls 'flushProducer' in a loop, which
-- polls with a 100 ms timeout (a safe FFI call, so other threads keep
-- running). A no-op global delivery callback is installed because the
-- per-message callbacks are dispatched through it. 'publish' resolves when the delivery report of the
-- message arrives (librdkafka's own retries happen within the timeout).
-- librdkafka's log lines are forwarded to the JSON logger.
--
-- __Business Justification:__ A successor call answers only after its
-- event is safely on the bus, so the audit trail never misses a call that
-- a caller saw succeed.
--
-- __Thread Safety:__ safe; librdkafka producers are thread-safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
module Successor.Publisher
  ( Publisher,
    newPublisher,
    publish,
    brokerReachable,
    closePublisher,
  )
where

import Control.Concurrent (ThreadId, forkIO, killThread)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Monad (forever)
import Data.Aeson (toJSON)
import Data.ByteString (ByteString)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Kafka.Metadata (topicMetadata)
import Kafka.Producer
import Successor.Log (Level (..), Logger, logMsg)
import System.Timeout (timeout)

-- | A running producer.
--
-- __Description:__ Wraps the hw-kafka-client handle.
--
-- __Business Justification:__ Keeps Kafka types out of the service code.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data Publisher = Publisher
  { -- | The hw-kafka-client producer.
    producerHandle :: KafkaProducer,
    -- | The thread polling librdkafka for delivery reports.
    poller :: ThreadId
  }

-- | Creates the producer.
--
-- __Description:__ Connects lazily to @brokers@ (comma-separated
-- @host:port@); librdkafka logs up to @kafkaLevel@ (syslog 0..7) become
-- @warn@ or @error@ JSON lines.
--
-- __Business Justification:__ Startup of the service.
--
-- __Parameters:__
--
-- * @logger@: the JSON logger.
-- * @brokers@: bootstrap servers.
-- * @kafkaLevel@: librdkafka log level.
--
-- __Returns:__ the producer, or the Kafka error.
--
-- __Errors:__ @Left@ for an invalid configuration.
--
-- __Side Effects:__ starts librdkafka threads and the polling thread.
--
-- __Complexity:__ O(1).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @newPublisher logger "redpanda:9092" 4@.
--
-- __See Also:__ 'publish', 'closePublisher'.
newPublisher :: Logger -> Text -> Int -> IO (Either Text Publisher)
newPublisher logger brokers kafkaLevel = do
  let props =
        brokersList [BrokerAddress (Text.strip b) | b <- Text.splitOn "," brokers]
          <> extraProps
            ( Map.fromList
                [ ("client.id", "successor"),
                  ("enable.idempotence", "true"),
                  ("acks", "all"),
                  ("message.timeout.ms", "1000"),
                  ("linger.ms", "0"),
                  ("log_level", Text.pack (show kafkaLevel))
                ]
            )
          <> setCallback (logCallback forward)
          -- hw-kafka-client dispatches the per-message callbacks of
          -- produceMessage' from its delivery callback, so one must be
          -- installed even though it has nothing to do itself.
          <> setCallback (deliveryCallback (const (pure ())))
      forward level facility message =
        logMsg
          logger
          (severity level)
          Nothing
          Nothing
          "librdkafka"
          [("facility", toJSON facility), ("detail", toJSON message), ("kafkaLevel", toJSON (show level))]
      severity = \case
        KafkaLogEmerg -> Error
        KafkaLogAlert -> Error
        KafkaLogCrit -> Error
        KafkaLogErr -> Error
        _ -> Warn
  created <- newProducer props
  case created of
    Left err -> pure (Left (Text.pack (show err)))
    Right producer -> Right . Publisher producer <$> forkIO (forever (flushProducer producer))

-- | Publishes one message and waits for its acknowledgement.
--
-- __Description:__ Sends @value@ keyed by @key@ to @topic@ (default
-- partitioner) and blocks until the delivery report arrives, at most
-- 1.5 s.
--
-- __Business Justification:__ See the module documentation.
--
-- __Parameters:__
--
-- * @publisher@: the producer.
-- * @topicName@: the topic.
-- * @key@: the message key (the task).
-- * @value@: the message.
--
-- __Returns:__ @Right ()@ once acknowledged.
--
-- __Errors:__ @Left@ for an immediate error (queue full), a delivery
-- failure or no report within 1.5 s.
--
-- __Side Effects:__ one Kafka message.
--
-- __Complexity:__ O(size of the message) plus the broker round trip.
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @publish p "aaas.successor.called.v1" taskId eventBytes@.
--
-- __See Also:__ 'Successor.Event.successorCalled'.
publish :: Publisher -> Text -> ByteString -> ByteString -> IO (Either Text ())
publish publisher topicName key value = do
  let producer = producerHandle publisher
  done <- newEmptyMVar
  let record =
        ProducerRecord
          { prTopic = TopicName topicName,
            prPartition = UnassignedPartition,
            prKey = Just key,
            prValue = Just value,
            prHeaders = mempty
          }
  sent <- produceMessage' producer record (putMVar done)
  case sent of
    Left err -> pure (Left ("produce: " <> Text.pack (show err)))
    Right () -> do
      report <- timeout 1500000 (takeMVar done)
      pure $ case report of
        Just (DeliverySuccess _ _) -> Right ()
        Just (DeliveryFailure _ err) -> Left ("delivery: " <> Text.pack (show err))
        Just (NoMessageError err) -> Left ("delivery: " <> Text.pack (show err))
        Nothing -> Left "delivery: no report within 1.5 s"

-- | Tells whether the broker answers a metadata request.
--
-- __Description:__ Asks for the metadata of @topicName@ with a 1 s timeout.
--
-- __Business Justification:__ The @broker@ check of @GET /health@.
--
-- __Parameters:__
--
-- * @publisher@: the producer.
-- * @topicName@: a topic that must exist.
--
-- __Returns:__ 'True' if the broker answered.
--
-- __Errors:__ None; failures return 'False'.
--
-- __Side Effects:__ one metadata request.
--
-- __Complexity:__ O(1).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @brokerReachable p "aaas.successor.called.v1"@.
--
-- __See Also:__ 'Successor.Api.application'.
brokerReachable :: Publisher -> Text -> IO Bool
brokerReachable publisher topicName =
  either (const False) (const True) <$> topicMetadata (producerHandle publisher) (Timeout 1000) (TopicName topicName)

-- | Flushes outstanding messages and closes the producer.
--
-- __Description:__ Stops the polling thread, then hw-kafka-client's
-- 'closeProducer' flushes the outstanding messages.
--
-- __Business Justification:__ Graceful shutdown (CLAUDE.md 6.1).
--
-- __Parameters:__
--
-- * @publisher@: the producer.
--
-- __Returns:__ nothing.
--
-- __Errors:__ None.
--
-- __Side Effects:__ network flush; stops librdkafka threads.
--
-- __Complexity:__ O(outstanding messages).
--
-- __Thread Safety:__ call once, after the last 'publish'.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @closePublisher p@.
--
-- __See Also:__ 'newPublisher'.
closePublisher :: Publisher -> IO ()
closePublisher publisher = do
  killThread (poller publisher)
  closeProducer (producerHandle publisher)
