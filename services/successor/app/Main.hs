-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       successor
-- Module:          Main
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Process entry point of the successor service:
--                  configuration, CouchDB migrations, Kafka producer, HTTP
--                  server and graceful shutdown on SIGTERM.
-- Related Docs:    services/successor/README.md, services/successor/docs/RUNBOOK.md,
--                  CLAUDE.md 6.1, ADR-0016

-- | Entry point of the successor service.
--
-- __Description:__ Startup order: configuration, logger, CouchDB
-- migrations (retried for up to 60 s while the database starts), Kafka
-- producer, metrics, HTTP server on port 8080. SIGTERM and SIGINT stop
-- accepting connections, let requests in flight finish for up to 8 s,
-- flush the producer and exit 0; a watchdog exits 1 after 9 s if any of
-- that hangs. A startup failure exits 1 with a @fatal@ log line.
--
-- __Business Justification:__ Migrations at startup and graceful shutdown
-- within 10 s (CLAUDE.md 6.1).
--
-- __Thread Safety:__ not applicable (process entry point).
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
module Main (main) where

import Control.Concurrent (forkIO, threadDelay)
import Control.Exception (SomeException, try)
import Data.Aeson (toJSON)
import Data.Text (Text)
import Data.Text qualified as Text
import Network.Wai.Handler.Warp
  ( defaultSettings,
    runSettings,
    setGracefulShutdownTimeout,
    setInstallShutdownHandler,
    setPort,
  )
import Successor.Api (Env (..), application)
import Successor.CallLog (migrate, newCallLog, ping, record)
import Successor.Config (Config (..), loadConfig)
import Successor.Event qualified as Event
import Successor.Identifiers (newUuidV7, nowMillis)
import Successor.Log (Level (..), Logger, logMsg, newLogger)
import Successor.Metrics (newMetrics, render)
import Successor.Publisher (brokerReachable, closePublisher, newPublisher, publish)
import Successor.Service (Deps (..))
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..), exitWith)
import System.Posix.Process (exitImmediately)
import System.Posix.Signals (Handler (Catch), installHandler, sigINT, sigTERM)

-- | Version of the service, as in CHANGELOG.md and the OCI label.
--
-- __Description:__ SemVer of successor.
--
-- __Business Justification:__ @successor_build_info@ and the startup log.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
version :: Text
version = "0.1.0"

-- | Logs a fatal error and exits with status 1.
--
-- __Description:__ One @fatal@ line, then exit.
--
-- __Business Justification:__ A misconfigured service stops with a reason.
--
-- __Parameters:__
--
-- * @logger@: the logger.
-- * @message@: why the process stops.
--
-- __Returns:__ never.
--
-- __Errors:__ None.
--
-- __Side Effects:__ one log line; ends the process.
--
-- __Complexity:__ O(1).
--
-- __Thread Safety:__ not applicable.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @die' logger "SUCCESSOR_DB_PASSWORD is required"@.
--
-- __See Also:__ 'main'.
die' :: Logger -> Text -> IO a
die' logger message = do
  logMsg logger Fatal Nothing Nothing message []
  exitWith (ExitFailure 1)

-- | Applies the migrations, retrying while CouchDB starts.
--
-- __Description:__ Up to 30 attempts, 2 s apart.
--
-- __Business Justification:__ The database container may become healthy
-- after the service starts.
--
-- __Parameters:__
--
-- * @logger@: the logger.
-- * @action@: the migration run.
-- * @attemptsLeft@: remaining attempts.
--
-- __Returns:__ the number of migrations applied.
--
-- __Errors:__ exits the process after the last attempt.
--
-- __Side Effects:__ those of the migration; log lines; sleeps.
--
-- __Complexity:__ at most 30 attempts.
--
-- __Thread Safety:__ not applicable.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @migrateWithRetry logger (migrate db dir) 30@.
--
-- __See Also:__ 'Successor.CallLog.migrate'.
migrateWithRetry :: Logger -> IO Int -> Int -> IO Int
migrateWithRetry logger action attemptsLeft = do
  result <- try action
  case result of
    Right n -> pure n
    Left (e :: SomeException)
      | attemptsLeft <= 1 -> die' logger ("database migrations failed: " <> Text.pack (show e))
      | otherwise -> do
          logMsg logger Warn Nothing Nothing "waiting for the database" [("error", toJSON (takeWhile (/= '\n') (show e)))]
          threadDelay 2000000
          migrateWithRetry logger action (attemptsLeft - 1)

-- | Runs the service.
--
-- __Description:__ See the module documentation.
--
-- __Business Justification:__ The successor process.
--
-- __Parameters:__ None.
--
-- __Returns:__ when the server has stopped.
--
-- __Errors:__ exits 1 on a startup failure.
--
-- __Side Effects:__ all of the service's I/O.
--
-- __Complexity:__ runs until stopped.
--
-- __Thread Safety:__ not applicable.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ the container's entry point.
--
-- __See Also:__ 'Successor.Api.application'.
main :: IO ()
main = do
  env <- getEnvironment
  bootLogger <- newLogger "successor" Info
  config <- either (die' bootLogger) pure (loadConfig (`lookup` env))
  logger <- newLogger (service config) (logLevel config)
  db <- newCallLog (dbUrl config) (dbUser config) (dbPassword config)
  applied <- migrateWithRetry logger (migrate db (migrationsDir config)) 30
  logMsg logger Info Nothing Nothing "database ready" [("migrationsApplied", toJSON applied)]
  publisher <- newPublisher logger (brokers config) (kafkaLogLevel config) >>= either (die' logger . ("kafka: " <>)) pure
  metrics <- newMetrics version
  let deps =
        Deps
          { recordCall = record db,
            publishEvent = publish publisher Event.topic,
            clock = nowMillis,
            freshId = newUuidV7
          }
      appEnv =
        Env
          { deps = deps,
            logger = logger,
            metrics = metrics,
            checks = [("database", ping db), ("broker", brokerReachable publisher Event.topic)],
            renderMetrics = render
          }
      onStop closeSocket = do
        let handler name = Catch $ do
              logMsg logger Info Nothing Nothing "stop requested" [("signal", toJSON (name :: Text))]
              _ <- forkIO (threadDelay 9000000 >> exitImmediately (ExitFailure 1))
              closeSocket
        _ <- installHandler sigTERM (handler "SIGTERM") Nothing
        _ <- installHandler sigINT (handler "SIGINT") Nothing
        pure ()
      settings =
        setPort (httpPort config)
          . setGracefulShutdownTimeout (Just 8)
          . setInstallShutdownHandler onStop
          $ defaultSettings
  logMsg logger Info Nothing Nothing "successor started" [("version", toJSON version), ("httpPort", toJSON (httpPort config))]
  runSettings settings (application appEnv)
  closePublisher publisher
  logMsg logger Info Nothing Nothing "successor stopped" []
