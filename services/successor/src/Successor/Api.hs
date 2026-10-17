-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       successor
-- Module:          Successor.Api
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         HTTP interface of the successor service on port 8080:
--                  POST /v1/next, GET /health and GET /metrics.
-- Related Docs:    services/successor/docs/API.md, CLAUDE.md 4.1 (RFC 9457),
--                  4.3 (Next) and 6.1, ADR-0016

-- | The HTTP interface.
--
-- __Description:__
--
-- * @POST \/v1\/next@ with @{"n": \<integer\>, "taskId": \<uuid\>}@ answers
--   @200 {"n": n + 1}@: the @Next({n}) → {n}@ method of CLAUDE.md 4.3 over
--   HTTP/JSON until the gRPC contracts of P2.1 exist. A @traceparent@
--   header is continued. Problems (RFC 9457): 400 for a malformed body,
--   422 for an argument outside @0..199997@ or a malformed @taskId@, 503
--   when CouchDB or Kafka failed.
-- * @GET \/health@: @{"status", "checks": {"database", "broker"}}@, 200 or
--   503.
-- * @GET \/metrics@: Prometheus text format.
--
-- Other paths answer 404 and other methods 405, as problems.
--
-- __Business Justification:__ The interface the ledger (P1.7) and later
-- the saga call @b@ times per addition.
--
-- __Thread Safety:__ safe; warp serves requests concurrently.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
module Successor.Api
  ( Env (..),
    application,
    parseNextRequest,
    problem,
  )
where

import Data.Aeson (Value (..), object, (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy qualified as BL
import Data.Scientific (floatingOrInteger)
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import Network.HTTP.Types
  ( Status,
    hContentType,
    methodGet,
    methodPost,
    status200,
    status400,
    status404,
    status405,
    status413,
    status422,
    status503,
    statusCode,
  )
import Network.Wai (Application, Response, lazyRequestBody, pathInfo, requestHeaders, requestMethod, responseLBS)
import Successor.Core (describeError)
import Successor.Identifiers (isUuid)
import Successor.Log (Level (..), Logger, logMsg)
import Successor.Metrics (Metrics, countCall, countDependencyFailure, observeDuration)
import Successor.Service (CallRequest (..), Deps, Failure (..), Outcome (..), call)
import Successor.Trace (childSpan, parseTraceparent)

-- | Everything the application needs.
--
-- __Description:__ Service dependencies, logger, metrics, named health
-- checks and the metrics renderer.
--
-- __Business Justification:__ Built once in @Main@ (or by the tests).
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data Env = Env
  { -- | Side effects of a call.
    deps :: Deps,
    -- | JSON logger.
    logger :: Logger,
    -- | Registered metrics.
    metrics :: Metrics,
    -- | Named checks of @GET /health@.
    checks :: [(Text, IO Bool)],
    -- | Body of @GET /metrics@.
    renderMetrics :: IO BL.ByteString
  }

-- | Builds an RFC 9457 problem response.
--
-- __Description:__ @{"type":"about:blank","title","status","detail"}@ as
-- @application/problem+json@.
--
-- __Business Justification:__ API errors are problem details (CLAUDE.md
-- 4.1).
--
-- __Parameters:__
--
-- * @status@: the HTTP status.
-- * @title@: the reason phrase.
-- * @detail@: the explanation (no internal details).
--
-- __Returns:__ the response.
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
-- __Example:__ @problem status404 "Not Found" "no endpoint /x"@.
--
-- __See Also:__ 'application'.
problem :: Status -> Text -> Text -> Response
problem status title detail =
  responseLBS status [(hContentType, "application/problem+json")] $
    Aeson.encode (object ["type" .= ("about:blank" :: Text), "title" .= title, "status" .= statusCode status, "detail" .= detail])

-- | Validates the body of @POST /v1/next@.
--
-- __Description:__ A JSON object with an integer @n@ (no fraction) and a
-- lowercase UUID @taskId@; other fields are ignored. The range of @n@ is
-- checked later by 'Successor.Core.next'.
--
-- __Business Justification:__ Malformed requests are refused before any
-- side effect.
--
-- __Parameters:__
--
-- * @body@: the request body.
--
-- __Returns:__ @(n, taskId)@, or the status and detail of the problem.
--
-- __Errors:__ 400 for invalid JSON or a missing/non-integer @n@; 422 for a
-- malformed @taskId@.
--
-- __Side Effects:__ None.
--
-- __Complexity:__ O(size of the body).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__
--
-- >>> parseNextRequest "{\"n\":3,\"taskId\":\"018f3c2e-7b1a-7c3d-9f00-0000000000aa\"}"
-- Right (3,"018f3c2e-7b1a-7c3d-9f00-0000000000aa")
-- >>> fmap fst (parseNextRequest "{\"n\":3.5,\"taskId\":\"x\"}")
-- Left (Status {statusCode = 400, statusMessage = "Bad Request"},"n must be an integer")
--
-- __See Also:__ 'application'.
parseNextRequest :: BL.ByteString -> Either (Status, Text) (Integer, Text)
parseNextRequest body = case Aeson.decode body of
  Just (Object o) -> do
    n <- case KeyMap.lookup "n" o of
      Just (Number s) -> either (const (Left (status400, "n must be an integer"))) Right (floatingOrInteger s :: Either Double Integer)
      _ -> Left (status400, "n must be an integer")
    case KeyMap.lookup "taskId" o of
      Just (String t) | isUuid t -> Right (n, t)
      _ -> Left (status422, "taskId must be a lowercase UUID")
  _ -> Left (status400, "the body must be a JSON object {\"n\": <integer>, \"taskId\": <uuid>}")

-- | The WAI application.
--
-- __Description:__ See the module documentation. Bodies above 4 KiB are
-- refused with 413.
--
-- __Business Justification:__ The whole HTTP surface of the service.
--
-- __Parameters:__
--
-- * @env@: the environment.
--
-- __Returns:__ the application.
--
-- __Errors:__ None; every failure is a problem response.
--
-- __Side Effects:__ those of 'Successor.Service.call' and the checks; one
-- debug log line per call, a warn line per failure; metrics.
--
-- __Complexity:__ O(size of the body) plus the call.
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @run 8080 (application env)@.
--
-- __See Also:__ 'Successor.Service.call'.
application :: Env -> Application
application env req respond = case (pathInfo req, requestMethod req) of
  (["v1", "next"], m) | m == methodPost -> do
    -- TEMPORARY(P2.1): HTTP/JSON stands in for the gRPC method Next of
    -- CLAUDE.md 4.3 until contracts/proto exists.
    body <- lazyRequestBody req
    if BL.length body > 4096
      then respond (problem status413 "Content Too Large" "the body is limited to 4 KiB")
      else case parseNextRequest body of
        Left (status, detail) -> do
          countCall (metrics env) "rejected"
          respond (problem status "Invalid Request" detail)
        Right (n, taskId) -> serve n taskId
  (["health"], m) | m == methodGet -> do
    results <- traverse (\(name, check) -> (name,) <$> check) (checks env)
    let healthy = all snd results
    respond . responseLBS (if healthy then status200 else status503) [(hContentType, "application/json")] $
      Aeson.encode
        ( object
            [ "status" .= (if healthy then "ok" else "error" :: Text),
              "checks" .= object [(Key.fromText name, String (if ok then "ok" else "error")) | (name, ok) <- results]
            ]
        )
  (["metrics"], m) | m == methodGet -> do
    text <- renderMetrics env
    respond (responseLBS status200 [(hContentType, "text/plain; version=0.0.4; charset=utf-8")] text)
  (path, _)
    | path `elem` [["v1", "next"], ["health"], ["metrics"]] ->
        respond (problem status405 "Method Not Allowed" "use POST for /v1/next and GET for /health and /metrics")
    | otherwise -> respond (problem status404 "Not Found" "no such endpoint")
  where
    serve n taskId = do
      started <- getCurrentTime
      span' <- childSpan (lookup "traceparent" (requestHeaders req) >>= parseTraceparent . TE.decodeUtf8)
      result <- call (deps env) (CallRequest n taskId span')
      finished <- getCurrentTime
      observeDuration (metrics env) (realToFrac (diffUTCTime finished started))
      let say level = logMsg (logger env) level (Just taskId) (Just span')
      case result of
        Right outcome -> do
          let (label, value) = case outcome of
                Computed r -> ("computed", r)
                Replayed r -> ("replayed", r)
          countCall (metrics env) label
          say Debug "successor computed" [("n", Aeson.toJSON n), ("result", Aeson.toJSON value), ("outcome", String label)]
          respond (responseLBS status200 [(hContentType, "application/json")] (Aeson.encode (object ["n" .= value])))
        Left (InvalidArgument err) -> do
          countCall (metrics env) "rejected"
          say Warn "argument outside the domain" [("n", Aeson.toJSON n)]
          respond (problem status422 "Unprocessable Content" (describeError err))
        Left (DependencyFailed dependency cause) -> do
          countCall (metrics env) "failed"
          countDependencyFailure (metrics env) dependency
          say Error "successor call failed" [("dependency", String dependency), ("error", String cause)]
          respond (problem status503 "Service Unavailable" ("the " <> dependency <> " dependency is unavailable; retry the call"))
