(*
   SPDX-License-Identifier: MIT
   Copyright (c) 2026 AaaS Contributors

   Component:       parser
   Module:          Aaas_parser.Config
   Owning Team:     Arithmetic Excellence Center (AEC)
   Classification:  INTERNAL
   Purpose:         Configuration of the parser read from environment
                    variables (bootstrap mode `env`).
   Related Docs:    services/parser/README.md (Configuration), CLAUDE.md 3
                    (platform at startup), ADR-0015
 *)

(** Service configuration.

    {b Description:} Until step P5.2 every service reads its configuration from
    environment variables ([AAAS_BOOTSTRAP=env]). The mode [platform]
    (config-server and OpenBao) is refused with a clear error until P5.2
    delivers it. The variables and defaults are listed in the README.

    {b Business Justification:} "Configuration only through env / config-server;
    no hard-coded hosts or passwords" (CLAUDE.md 6.1).

    {b Thread Safety:} pure functions; safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)

(** The configuration of one parser process.

    {b Description:}
    - [service]: [AAAS_SERVICE], default ["parser"];
    - [env]: [AAAS_ENV], default ["local"];
    - [http_port]: [AAAS_HTTP_PORT], default [8080];
    - [brokers]: [AAAS_KAFKA_BROKERS], default ["redpanda:9092"];
    - [consumer_group]: [AAAS_CONSUMER_GROUP], default ["parser"];
    - [db_path]: [AAAS_DB_PATH], default ["/data/parser.db"];
    - [migrations_dir]: [AAAS_MIGRATIONS_DIR], default ["/app/migrations"];
    - [log_level]: [AAAS_LOG_LEVEL], default [info];
    - [kafka_log_level]: [AAAS_KAFKA_LOG_LEVEL], the syslog level (0..7) up to
      which librdkafka writes its own plain-text lines to stderr, default [0]
      (silent), because those lines are not JSON (CLAUDE.md 6.1) and the
      bindings cannot redirect them; raise it only while debugging.

    {b Business Justification:} Everything the process needs to start.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
type t = {
  service : string;
  env : string;
  http_port : int;
  brokers : string;
  consumer_group : string;
  db_path : string;
  migrations_dir : string;
  log_level : Log.level;
  kafka_log_level : int;
}

(** Reads the configuration from a variable lookup.

    {b Description:} [getenv] returns the value of a variable or [None]; empty
    values count as unset. [AAAS_BOOTSTRAP] must be [env] (the default).

    {b Business Justification:} One validated configuration at startup; a
    mistake stops the process with a message instead of misbehaving later.

    {b Errors:} [Error message] for [AAAS_BOOTSTRAP=platform] (not available
    before P5.2) or another unknown mode, a port that is not an integer in
    [1..65535], an unknown log level, or a Kafka log level outside [0..7].

    {b Side Effects:} None (the lookup is supplied by the caller).

    {b Complexity:} O(1).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      (Result.get_ok (load (fun _ -> None))).brokers = "redpanda:9092"
    ]}

    {b See Also:} [Sys.getenv_opt].

    @param getenv the variable lookup, usually [Sys.getenv_opt].
    @return the configuration, or the first error.
    @since parser 0.1.0 *)
let load getenv =
  let get name default =
    match getenv name with Some v when v <> "" -> v | _ -> default
  in
  match get "AAAS_BOOTSTRAP" "env" with
  | "platform" ->
      Error
        "AAAS_BOOTSTRAP=platform is not available yet: config-server and \
         OpenBao arrive in steps P5.2 and P5.3; use AAAS_BOOTSTRAP=env"
  | "env" -> (
      let port_text = get "AAAS_HTTP_PORT" "8080" in
      let kafka_text = get "AAAS_KAFKA_LOG_LEVEL" "0" in
      match
        ( int_of_string_opt port_text,
          Log.level_of_string (get "AAAS_LOG_LEVEL" "info"),
          int_of_string_opt kafka_text )
      with
      | Some http_port, Some log_level, Some kafka_log_level
        when http_port >= 1 && http_port <= 65535 && kafka_log_level >= 0
             && kafka_log_level <= 7 ->
          Ok
            {
              service = get "AAAS_SERVICE" "parser";
              env = get "AAAS_ENV" "local";
              http_port;
              brokers = get "AAAS_KAFKA_BROKERS" "redpanda:9092";
              consumer_group = get "AAAS_CONSUMER_GROUP" "parser";
              db_path = get "AAAS_DB_PATH" "/data/parser.db";
              migrations_dir = get "AAAS_MIGRATIONS_DIR" "/app/migrations";
              log_level;
              kafka_log_level;
            }
      | _, None, _ ->
          Error
            "AAAS_LOG_LEVEL: expected one of debug, info, warn, error, fatal"
      | Some p, _, _ when p >= 1 && p <= 65535 ->
          Error ("AAAS_KAFKA_LOG_LEVEL: expected 0..7, got " ^ kafka_text)
      | _ -> Error ("AAAS_HTTP_PORT: expected a port number, got " ^ port_text))
  | other -> Error ("AAAS_BOOTSTRAP: expected env or platform, got " ^ other)
