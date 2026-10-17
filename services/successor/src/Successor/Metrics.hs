-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       successor
-- Module:          Successor.Metrics
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Prometheus metrics of the successor service.
-- Related Docs:    services/successor/docs/SLO.md, CLAUDE.md 6.1, ADR-0016

-- | Prometheus metrics.
--
-- __Description:__ Registered in the global registry of
-- prometheus-client and rendered by 'render':
--
-- * @successor_calls_total{outcome}@: calls by outcome (@computed@,
--   @replayed@, @rejected@, @failed@);
-- * @successor_call_duration_seconds@: histogram of served calls;
-- * @successor_dependency_failures_total{dependency}@: failed calls to
--   @couchdb@ or @kafka@ after their retries;
-- * @successor_build_info{version}@: always 1.
--
-- __Business Justification:__ "Successor/s" is a dashboard of P7.3 and
-- the SLO of SLO.md is measured from these series.
--
-- __Thread Safety:__ safe (prometheus-client uses atomic updates).
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
module Successor.Metrics
  ( Metrics (..),
    newMetrics,
    countCall,
    countDependencyFailure,
    observeDuration,
    render,
  )
where

import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Prometheus hiding (observeDuration)

-- | The registered metrics.
--
-- __Description:__ One field per metric of the module documentation.
--
-- __Business Justification:__ Passed explicitly to the service code.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data Metrics = Metrics
  { -- | @successor_calls_total{outcome}@.
    calls :: Vector Label1 Counter,
    -- | @successor_call_duration_seconds@.
    duration :: Histogram,
    -- | @successor_dependency_failures_total{dependency}@.
    dependencyFailures :: Vector Label1 Counter
  }

-- | Registers the metrics.
--
-- __Description:__ Must be called once per process: registering twice
-- exports duplicate series.
--
-- __Business Justification:__ Startup of the service.
--
-- __Parameters:__
--
-- * @version@: the service version for @successor_build_info@.
--
-- __Returns:__ the metrics.
--
-- __Errors:__ None.
--
-- __Side Effects:__ adds to the global registry.
--
-- __Complexity:__ O(1).
--
-- __Thread Safety:__ call once.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @newMetrics "0.1.0"@.
--
-- __See Also:__ 'render'.
newMetrics :: Text -> IO Metrics
newMetrics version = do
  info <- register (vector "version" (gauge (Info "successor_build_info" "Version of the running successor.")))
  withLabel info version (`setGauge` 1)
  Metrics
    <$> register (vector "outcome" (counter (Info "successor_calls_total" "Successor calls by outcome.")))
    <*> register
      ( histogram
          (Info "successor_call_duration_seconds" "Time to serve a successor call.")
          [0.001, 0.0025, 0.005, 0.01, 0.02, 0.05, 0.1, 0.25, 0.5, 1, 2]
      )
    <*> register (vector "dependency" (counter (Info "successor_dependency_failures_total" "Failed calls to a dependency after retries.")))

-- | Counts one call with its outcome.
--
-- __Description:__ Increments @successor_calls_total{outcome}@.
--
-- __Business Justification:__ Throughput and correctness.
--
-- __Parameters:__
--
-- * @m@: the metrics.
-- * @outcome@: @computed@, @replayed@, @rejected@ or @failed@.
--
-- __Returns:__ nothing.
--
-- __Errors:__ None.
--
-- __Side Effects:__ updates the counter.
--
-- __Complexity:__ O(1).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @countCall m "computed"@.
--
-- __See Also:__ 'Successor.Api.application'.
countCall :: Metrics -> Text -> IO ()
countCall m outcome = withLabel (calls m) outcome incCounter

-- | Counts one dependency failure.
--
-- __Description:__ Increments @successor_dependency_failures_total{dependency}@.
--
-- __Business Justification:__ Tells CouchDB trouble from broker trouble
-- (RUNBOOK.md).
--
-- __Parameters:__
--
-- * @m@: the metrics.
-- * @dependency@: @couchdb@ or @kafka@.
--
-- __Returns:__ nothing.
--
-- __Errors:__ None.
--
-- __Side Effects:__ updates the counter.
--
-- __Complexity:__ O(1).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @countDependencyFailure m "kafka"@.
--
-- __See Also:__ 'Successor.Service.call'.
countDependencyFailure :: Metrics -> Text -> IO ()
countDependencyFailure m dependency = withLabel (dependencyFailures m) dependency incCounter

-- | Records the duration of a served call.
--
-- __Description:__ Observes the histogram.
--
-- __Business Justification:__ The latency SLI.
--
-- __Parameters:__
--
-- * @m@: the metrics.
-- * @seconds@: the duration.
--
-- __Returns:__ nothing.
--
-- __Errors:__ None.
--
-- __Side Effects:__ updates the histogram.
--
-- __Complexity:__ O(number of buckets).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @observeDuration m 0.004@.
--
-- __See Also:__ 'countCall'.
observeDuration :: Metrics -> Double -> IO ()
observeDuration m = observe (duration m)

-- | Renders every registered metric in the text format.
--
-- __Description:__ prometheus-client's exposition format 0.0.4.
--
-- __Business Justification:__ The body of @GET /metrics@.
--
-- __Parameters:__ None.
--
-- __Returns:__ the exposition text.
--
-- __Errors:__ None.
--
-- __Side Effects:__ reads the registry.
--
-- __Complexity:__ O(number of samples).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @render@ contains @successor_calls_total@.
--
-- __See Also:__ 'newMetrics'.
render :: IO BL.ByteString
render = exportMetricsAsText
