(*
   SPDX-License-Identifier: MIT
   Copyright (c) 2026 AaaS Contributors

   Component:       parser
   Module:          Aaas_parser.Http
   Owning Team:     Arithmetic Excellence Center (AEC)
   Classification:  INTERNAL
   Purpose:         HTTP endpoints of the parser on port 8080: GET /health
                    and GET /metrics.
   Related Docs:    services/parser/docs/API.md, CLAUDE.md 4.1 (RFC 9457) and
                    6.1, ADR-0015
 *)

(** HTTP server of the parser.

    {b Description:} The parser has no public API; it serves only the
    operational endpoints every service has (CLAUDE.md 6.1):
    - [GET /health]: [{"status":"ok"|"error","checks":{...}}] with 200 when
      every check passes and 503 otherwise;
    - [GET /metrics]: Prometheus text format.

    Other paths answer 404 and other methods on these paths 405, both as
    [application/problem+json] (RFC 9457).

    {b Business Justification:} Liveness and readiness for Compose and Consul
    (P5.1); metrics for Prometheus (P7.1).

    {b Thread Safety:} one Lwt thread.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)

(** A named health check.

    {b Description:} The name appears in [checks]; the function resolves to
    [true] when the dependency is fine.

    {b Business Justification:} The checks are supplied by the caller (database,
    broker, consumer), which keeps this module testable.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
type check = string * (unit -> bool Lwt.t)

(** A response before it is sent.

    {b Description:} Status code, content type and body.

    {b Business Justification:} Lets the routes be tested without a socket.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
type response = { status : int; content_type : string; body : string }

(** Builds an RFC 9457 problem response.

    {b Description:}
    [{"type":"about:blank","title":...,"status":..., "detail":...}] with
    [application/problem+json].

    {b Business Justification:} API errors are always problem details (CLAUDE.md
    4.1).

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(1).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      (problem 404 "Not Found" "no such endpoint").status = 404
    ]}

    {b See Also:} {!routes}.

    @param status the HTTP status code.
    @param title the reason phrase.
    @param detail the explanation.
    @return the response.
    @since parser 0.1.0 *)
let problem status title detail =
  {
    status;
    content_type = "application/problem+json";
    body =
      Yojson.Safe.to_string
        (`Assoc
           [
             ("type", `String "about:blank");
             ("title", `String title);
             ("status", `Int status);
             ("detail", `String detail);
           ]);
  }

(** Runs the health checks and builds the [/health] response.

    {b Description:} Runs every check (a check that raises counts as failed) and
    answers 200 with status [ok] if all pass, otherwise 503 with status [error];
    [checks] maps each name to ["ok"] or ["error"].

    {b Business Justification:} Liveness and readiness in one endpoint
    (CLAUDE.md 6.1).

    {b Errors:} None.

    {b Side Effects:} those of the checks.

    {b Complexity:} O(c) in the number of checks, plus their cost.

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      health [ ("database", fun () -> Lwt.return true) ]
    ]}

    {b See Also:} {!routes}.

    @param checks the named checks.
    @return a promise of the response.
    @since parser 0.1.0 *)
let health checks =
  Lwt.map
    (fun results ->
      let healthy = List.for_all snd results in
      {
        status = (if healthy then 200 else 503);
        content_type = "application/json";
        body =
          Yojson.Safe.to_string
            (`Assoc
               [
                 ("status", `String (if healthy then "ok" else "error"));
                 ( "checks",
                   `Assoc
                     (List.map
                        (fun (name, ok) ->
                          (name, `String (if ok then "ok" else "error")))
                        results) );
               ]);
      })
    (Lwt_list.map_s
       (fun (name, f) ->
         Lwt.map
           (fun ok -> (name, ok))
           (Lwt.catch f (fun _ -> Lwt.return false)))
       checks)

(** Routes a request to its response.

    {b Description:} See the module documentation for the endpoints.

    {b Business Justification:} The whole HTTP surface of the parser.

    {b Errors:} None; unknown requests get problem responses.

    {b Side Effects:} those of the health checks.

    {b Complexity:} as {!health} or {!Metrics.render}.

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      routes ~checks ~version:"0.1.0" ~meth:`GET ~path:"/metrics"
    ]}

    {b See Also:} {!serve}.

    @param checks the health checks.
    @param version the service version, for the metrics.
    @param meth the request method.
    @param path the request path, without the query.
    @return a promise of the response.
    @since parser 0.1.0 *)
let routes ~checks ~version ~meth ~path =
  match (meth, path) with
  | `GET, "/health" -> health checks
  | `GET, "/metrics" ->
      Lwt.return
        {
          status = 200;
          content_type = "text/plain; version=0.0.4; charset=utf-8";
          body = Metrics.render ~version;
        }
  | _, ("/health" | "/metrics") ->
      Lwt.return (problem 405 "Method Not Allowed" "only GET is supported")
  | _ -> Lwt.return (problem 404 "Not Found" ("no endpoint " ^ path))

(** Starts the HTTP server.

    {b Description:} Listens on all interfaces on [port] and serves {!routes}
    until [stop] resolves.

    {b Business Justification:} Port 8080 of CLAUDE.md 6.1.

    {b Errors:} [Unix.Unix_error] if the port cannot be bound.

    {b Side Effects:} binds a TCP port; answers requests.

    {b Complexity:} O(1) per request plus the route.

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      serve ~port:8080 ~checks ~version:"0.1.0" ~stop
    ]}

    {b See Also:} {!routes}.

    @param port the TCP port.
    @param checks the health checks.
    @param version the service version.
    @param stop a promise that stops the server when resolved.
    @return a promise resolved when the server stops.
    @since parser 0.1.0 *)
let serve ~port ~checks ~version ~stop =
  let callback _conn request _body =
    let uri = Cohttp.Request.uri request in
    Lwt.bind
      (routes ~checks ~version
         ~meth:(Cohttp.Request.meth request)
         ~path:(Uri.path uri))
      (fun r ->
        Cohttp_lwt_unix.Server.respond_string
          ~status:(Cohttp.Code.status_of_code r.status)
          ~headers:(Cohttp.Header.of_list [ ("content-type", r.content_type) ])
          ~body:r.body ())
  in
  Cohttp_lwt_unix.Server.create ~stop
    ~mode:(`TCP (`Port port))
    (Cohttp_lwt_unix.Server.make ~callback ())
