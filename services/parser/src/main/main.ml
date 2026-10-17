(*
   SPDX-License-Identifier: MIT
   Copyright (c) 2026 AaaS Contributors

   Component:       parser
   Module:          Main
   Owning Team:     Arithmetic Excellence Center (AEC)
   Classification:  INTERNAL
   Purpose:         Process entry point of the parser: configuration,
                    database migrations, HTTP server, Kafka consumer and
                    graceful shutdown on SIGTERM.
   Related Docs:    services/parser/README.md, services/parser/docs/RUNBOOK.md,
                    CLAUDE.md 6.1, ADR-0015
 *)

(** Entry point of the parser service.

    {b Description:} Startup order: configuration ({!Aaas_parser.Config}),
    database and migrations ({!Aaas_parser.Store}), HTTP server
    ({!Aaas_parser.Http}, so that [/health] answers while the broker is still
    starting), Kafka ({!Aaas_parser.Consumer}). SIGTERM and SIGINT stop the
    consumer after the current message, release Kafka, stop the HTTP server and
    close the database; a watchdog ends the process after 9 s if any of that
    hangs. Exit status 0 after a clean stop, 1 on a startup or runtime failure.

    {b Business Justification:} Graceful shutdown in at most 10 s and migrations
    at startup (CLAUDE.md 6.1).

    {b Thread Safety:} single process, one Lwt thread.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)

open Aaas_parser

(** Version of the service.

    {b Description:} SemVer of the parser (CHANGELOG.md), also in the OCI label
    of the image.

    {b Business Justification:} [parser_build_info] and the startup log.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let version = "0.1.0"

(** Seconds after a stop signal before the process exits regardless.

    {b Description:} 9 s, below the 10 s [stop_grace_period] of Compose.

    {b Business Justification:} Shutdown within 10 s (CLAUDE.md 6.1).

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let shutdown_deadline_s = 9

(** Logs a fatal error and exits with status 1.

    {b Description:} Writes one [fatal] line with the message.

    {b Business Justification:} A misconfigured service stops with a clear
    reason instead of running degraded.

    {b Errors:} None (does not return).

    {b Side Effects:} one log line; ends the process.

    {b Complexity:} O(1).

    {b Thread Safety:} not applicable.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      fail "AAAS_HTTP_PORT: expected a port number"
    ]}

    {b See Also:} {!main}.

    @param message why the process stops.
    @return never.
    @since parser 0.1.0 *)
let fail message =
  Log.emit Log.Fatal message;
  exit 1

(** Runs the service until a stop signal or a fatal error.

    {b Description:} See the module documentation.

    {b Business Justification:} The parser process.

    {b Errors:} Exits with status 1 on a configuration, database, broker or port
    binding failure.

    {b Side Effects:} all of the service's I/O.

    {b Complexity:} runs until stopped.

    {b Thread Safety:} not applicable.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      main ()
    ]}

    {b See Also:} {!Aaas_parser.Consumer.run}.

    @param unit no argument.
    @since parser 0.1.0 *)
let main () =
  Random.self_init ();
  let config =
    match Config.load Sys.getenv_opt with Ok c -> c | Error m -> fail m
  in
  Log.service := config.service;
  Log.min_level := config.log_level;
  let store =
    try
      let store = Store.open_db config.db_path in
      let applied = Store.migrate store ~dir:config.migrations_dir in
      Log.emit Log.Info "database ready"
        ~fields:
          [
            ("path", `String config.db_path); ("migrationsApplied", `Int applied);
          ];
      store
    with Store.Error m | Sys_error m -> fail ("database: " ^ m)
  in
  let stop, stop_wakener = Lwt.wait () in
  let request_stop signal =
    if Lwt.is_sleeping stop then (
      let name = if signal = Sys.sigterm then "SIGTERM" else "SIGINT" in
      Log.emit Log.Info "stop requested" ~fields:[ ("signal", `String name) ];
      ignore (Unix.alarm shutdown_deadline_s);
      Lwt.wakeup_later stop_wakener ())
  in
  Sys.set_signal Sys.sigalrm (Sys.Signal_handle (fun _ -> exit 1));
  List.iter
    (fun s -> ignore (Lwt_unix.on_signal s request_stop))
    [ Sys.sigterm; Sys.sigint ];
  let consumer = ref None in
  let checks =
    [
      ("database", fun () -> Lwt.return (Store.ping store));
      ( "broker",
        fun () ->
          Consumer.broker_reachable ~brokers:config.brokers ~timeout_s:1.0 );
      ( "consumer",
        fun () ->
          Lwt.return
            (match !consumer with
            | Some c -> Consumer.alive c ~max_age_s:15.
            | None -> false) );
    ]
  in
  let server = Http.serve ~port:config.http_port ~checks ~version ~stop in
  Log.emit Log.Info "parser started"
    ~fields:
      [ ("version", `String version); ("httpPort", `Int config.http_port) ];
  let work =
    Lwt.bind
      (Consumer.create ~brokers:config.brokers ~group:config.consumer_group
         ~kafka_log_level:config.kafka_log_level ~metadata_wait_s:60.) (fun c ->
        consumer := Some c;
        Log.emit Log.Info "consuming"
          ~fields:
            [
              ("topic", `String Event.input_topic);
              ("group", `String config.consumer_group);
              ("partitions", `List (List.map (fun p -> `Int p) c.partitions));
            ];
        Lwt.async (fun () -> Lwt.map (fun () -> Consumer.stop c) stop);
        Lwt.bind (Consumer.run c ~store) (fun () ->
            Consumer.close c ~flush_s:2.))
  in
  let outcome =
    Lwt_main.run
      (Lwt.catch
         (fun () ->
           Lwt.bind
             (Lwt.choose
                [
                  Lwt.map (fun () -> `Work_done) work;
                  Lwt.map (fun () -> `Stop) stop;
                  (* The server resolves only after a stop; it fails if
                     the port cannot be bound. *)
                  Lwt.map (fun () -> `Stop) server;
                ])
             (function
               | `Stop when Option.is_some !consumer ->
                   (* The consumer finishes its message and closes. *)
                   Lwt.map (fun () -> `Clean) work
               | `Stop | `Work_done -> Lwt.return `Clean))
         (fun e -> Lwt.return (`Failed (Printexc.to_string e))))
  in
  Store.close store;
  match outcome with
  | `Clean -> Log.emit Log.Info "parser stopped"
  | `Failed m -> fail ("stopped after an error: " ^ m)

(** Process entry.

    {b Description:} Calls {!main}.

    {b Business Justification:} OCaml executables start with their top-level
    effects.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let () = main ()
