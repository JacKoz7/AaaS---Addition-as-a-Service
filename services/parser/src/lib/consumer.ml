(*
   SPDX-License-Identifier: MIT
   Copyright (c) 2026 AaaS Contributors

   Component:       parser
   Module:          Aaas_parser.Consumer
   Owning Team:     Arithmetic Excellence Center (AEC)
   Classification:  INTERNAL
   Purpose:         Kafka wiring of the parser: consumes
                    aaas.expression.submitted.v1, processes every message
                    with retries, publishes aaas.addition.requested.v1 and
                    stores consumer offsets after processing.
   Related Docs:    services/parser/README.md, CLAUDE.md 4.2 and 6.1,
                    ADR-0011, ADR-0015
 *)

(** Kafka consumer and producer of the parser.

    {b Description:} Uses librdkafka through the OCaml [kafka] bindings
    (ADR-0015). The bindings offer the partition-level ("simple") consumer of
    librdkafka, not the group-balanced one, so one process consumes every
    partition of the input topic through one queue and commits its offsets to
    the consumer group [AAAS_CONSUMER_GROUP] (default [parser]). Offsets are
    stored only after a message is processed, and committed every second and
    when consumption stops: delivery is at least once, and redeliveries are
    absorbed by [processed_events] ({!Processor.handle}).

    Messages are processed one at a time, in order. A failed attempt (database
    or broker) is retried with exponential backoff and jitter; after three
    attempts the failure is logged as exhausted and the message keeps being
    retried every five seconds, because the dead-letter service does not exist
    yet.

    {b Business Justification:} Delivery of the addition request to the
    computation (CLAUDE.md 3, step 4) without losing or duplicating it.

    {b Thread Safety:} one Lwt thread; the Kafka calls that block run in the Lwt
    thread pool.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)

(** A running consumer.

    {b Description:} The librdkafka handles (consumer, its input topic and
    queue, producer and its output topic), the consumed partitions, the time of
    the last poll (for the health check) and the stop flag.

    {b Business Justification:} Everything {!run} and {!close} need.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
type t = {
  consumer : Kafka.handler;
  input : Kafka.topic;
  queue : Kafka.queue;
  partitions : int list;
  producer : Kafka.handler;
  output : Kafka.topic;
  mutable last_poll : float;
  mutable stopping : bool;
}

(** Timeout of one publication, in seconds.

    {b Description:} 2 s: librdkafka's [message.timeout.ms] is 2000, and the
    promise is abandoned slightly later if no delivery report arrives.

    {b Business Justification:} "Timeout 2 s" default of CLAUDE.md 6.1.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let publish_timeout_s = 2.5

(** Number of quick attempts before a failure is reported as exhausted.

    {b Description:} 3, the default of CLAUDE.md 6.1.

    {b Business Justification:} Rides out a broker leader election or a busy
    database without alarming anyone.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let quick_attempts = 3

(** Pause between attempts after the quick ones, in seconds.

    {b Description:} 5 s.

    {b Business Justification:} Keeps retrying a stuck message without flooding
    the log.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let slow_retry_s = 5.0

(** Backoff before the next quick attempt.

    {b Description:} [0.2 * 2^(attempt-1)] seconds with full jitter between 50%
    and 150%.

    {b Business Justification:} Retries with jitter (CLAUDE.md 6.1), so that
    several services do not retry in lockstep.

    {b Errors:} None.

    {b Side Effects:} draws from [Random].

    {b Complexity:} O(1).

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      backoff 1 >= 0.1 && backoff 1 <= 0.3
    ]}

    {b See Also:} {!process_with_retries}.

    @param attempt the number of the failed attempt, from 1.
    @return the pause in seconds.
    @since parser 0.1.0 *)
let backoff attempt =
  0.2 *. (2. ** float_of_int (attempt - 1)) *. (0.5 +. Random.float 1.0)

(** Creates the consumer and the producer.

    {b Description:} Connects to [brokers] (librdkafka writes its own log lines
    up to [kafka_log_level], see {!Config.t}), reads the partitions of the input
    topic (retrying for up to [metadata_wait_s] seconds while the broker starts)
    and starts consuming every partition from the offset committed for [group]
    (from the earliest offset for a new group). The producer is idempotent,
    waits for all in-sync replicas and gives up on a message after 2 s.

    {b Business Justification:} Startup of the event-driven part of the service.

    {b Errors:} [Kafka.Error] if the handles cannot be created or the topic
    metadata is not available in time.

    {b Side Effects:} network connections to the broker; consumption starts.

    {b Complexity:} O(p) in the number of partitions.

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      create ~brokers:"redpanda:9092" ~group:"parser" ~kafka_log_level:0
        ~metadata_wait_s:30.
    ]}

    {b See Also:} {!run}, {!close}.

    @param brokers comma-separated [host:port] list.
    @param group the consumer group of the committed offsets.
    @param kafka_log_level the librdkafka [log_level] (0..7).
    @param metadata_wait_s how long to wait for the topic metadata.
    @return a promise of the running consumer.
    @since parser 0.1.0 *)
let create ~brokers ~group ~kafka_log_level ~metadata_wait_s =
  let log_level = ("log_level", string_of_int kafka_log_level) in
  let consumer =
    Kafka.new_consumer
      [
        log_level;
        ("metadata.broker.list", brokers);
        ("client.id", "parser");
        ("group.id", group);
        ("enable.auto.offset.store", "false");
        ("enable.auto.commit", "true");
        ("auto.commit.interval.ms", "1000");
      ]
  in
  let input =
    Kafka.new_topic consumer Event.input_topic
      [ ("auto.offset.reset", "earliest") ]
  in
  let deadline = Unix.gettimeofday () +. metadata_wait_s in
  let rec partitions () =
    match Kafka.topic_metadata ~timeout_ms:2000 consumer input with
    | { Kafka.Metadata.topic_partitions = _ :: _ as ps; _ } ->
        Lwt.return (List.sort compare ps)
    | _ | (exception Kafka.Error _) ->
        if Unix.gettimeofday () > deadline then
          Lwt.fail
            (Kafka.Error
               (Kafka.TIMED_OUT, "no metadata for topic " ^ Event.input_topic))
        else (
          Log.emit Log.Warn "waiting for the broker"
            ~fields:[ ("brokers", `String brokers) ];
          Lwt.bind (Lwt_unix.sleep 1.0) partitions)
  in
  Lwt.map
    (fun partitions ->
      let queue = Kafka.new_queue consumer in
      List.iter
        (fun p -> Kafka.consume_start_queue queue input p Kafka.offset_stored)
        partitions;
      let producer =
        Kafka_lwt.new_producer ~delivery_check_period_ms:5
          [
            log_level;
            ("metadata.broker.list", brokers);
            ("client.id", "parser");
            ("enable.idempotence", "true");
            ("acks", "all");
          ]
      in
      let output =
        Kafka.new_topic producer Event.output_topic
          [ ("message.timeout.ms", "2000") ]
      in
      {
        consumer;
        input;
        queue;
        partitions;
        producer;
        output;
        last_poll = Unix.gettimeofday ();
        stopping = false;
      })
    (partitions ())

(** Publishes one message to [aaas.addition.requested.v1].

    {b Description:} Keyed by [key] (the task), partitioned by librdkafka's
    default partitioner; resolves on the delivery report and fails on a delivery
    error or after {!publish_timeout_s}.

    {b Business Justification:} The {!Processor.publisher} of the service.

    {b Errors:} [Kafka.Error] on a delivery error; [Lwt_unix.Timeout] when no
    report arrives in time.

    {b Side Effects:} one Kafka message; increments
    [parser_publish_failures_total] on failure.

    {b Complexity:} O(size of the message).

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      publish t ~key:task_id output_event
    ]}

    {b See Also:} {!Processor.publisher}.

    @param t the consumer.
    @param key the message key.
    @param value the message value.
    @return a promise resolved on acknowledgement.
    @since parser 0.1.0 *)
let publish t ~key value =
  Lwt.catch
    (fun () ->
      Lwt_unix.with_timeout publish_timeout_s (fun () ->
          Kafka_lwt.produce t.output Kafka.partition_unassigned ~key value))
    (fun e ->
      Metrics.inc Metrics.publish_failures;
      Lwt.fail e)

(** Processes one message until it succeeds or the consumer stops.

    {b Description:} Calls {!Processor.handle}; on an exception logs it, counts
    it in [parser_processing_failures_total] and retries (see the module
    documentation). Returns [true] once the message is processed and [false] if
    the consumer stopped first; the offset must then not be stored.

    {b Business Justification:} Local retries before giving up (CLAUDE.md 6.1).

    {b Errors:} None; failures are retried.

    {b Side Effects:} those of {!Processor.handle}; log lines; metrics.

    {b Complexity:} unbounded while the failure persists.

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      process_with_retries t ~store raw
    ]}

    {b See Also:} {!run}.

    @param t the consumer.
    @param store the parser database.
    @param value the message value.
    @return a promise of whether the message was processed.
    @since parser 0.1.0 *)
let process_with_retries t ~store value =
  let rec attempt n =
    if t.stopping then Lwt.return false
    else
      Lwt.catch
        (fun () ->
          Lwt.map
            (fun (_ : Processor.outcome) -> true)
            (Processor.handle ~store ~publish:(publish t)
               ~now_ms:(Timestamp.now_ms ()) value))
        (fun e ->
          Metrics.inc Metrics.processing_failures;
          let exhausted = n >= quick_attempts in
          (* TEMPORARY(P3.6): after the local retries the message is retried
             in place; P3.6 sends it to aaas.dlq.v1 instead. *)
          Log.emit
            (if exhausted then Log.Error else Log.Warn)
            (if exhausted then
               "processing failed, local retries exhausted; retrying in place"
             else "processing failed; retrying")
            ~fields:
              [ ("attempt", `Int n); ("error", `String (Printexc.to_string e)) ];
          let pause = if exhausted then slow_retry_s else backoff n in
          Lwt.bind (Lwt_unix.sleep pause) (fun () -> attempt (n + 1)))
  in
  attempt 1

(** Consumes and processes messages until {!stop} is called.

    {b Description:} Polls the queue for up to 500 ms at a time. A message is
    processed with {!process_with_retries} and its offset stored afterwards;
    partition ends and poll timeouts only refresh the heartbeat; other Kafka
    errors are logged and polling resumes after one second.

    {b Business Justification:} The main loop of the service.

    {b Errors:} None; an unexpected exception ends the loop and fails the
    promise, which stops the process.

    {b Side Effects:} consumes messages; stores offsets.

    {b Complexity:} O(1) per message plus its processing.

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      Lwt.async (fun () -> run t ~store)
    ]}

    {b See Also:} {!stop}.

    @param t the consumer.
    @param store the parser database.
    @return a promise resolved when the loop has stopped.
    @since parser 0.1.0 *)
let rec run t ~store =
  if t.stopping then Lwt.return_unit
  else
    Lwt.try_bind
      (fun () -> Kafka_lwt.consume_queue ~timeout_ms:500 t.queue)
      (function
        | Kafka.Message (topic, partition, offset, value, _key) ->
            t.last_poll <- Unix.gettimeofday ();
            Lwt.bind (process_with_retries t ~store value) (fun processed ->
                if processed then Kafka.store_offset topic partition offset;
                run t ~store)
        | Kafka.PartitionEnd _ ->
            t.last_poll <- Unix.gettimeofday ();
            run t ~store)
      (function
        | Kafka.Error (Kafka.TIMED_OUT, _) ->
            t.last_poll <- Unix.gettimeofday ();
            run t ~store
        | Kafka.Error (_, message) ->
            Log.emit Log.Warn "consumer error"
              ~fields:[ ("error", `String message) ];
            Lwt.bind (Lwt_unix.sleep 1.0) (fun () -> run t ~store)
        | e -> Lwt.fail e)

(** Asks {!run} to stop after the current message.

    {b Description:} Sets the stop flag; a message being retried is abandoned
    (its offset is not stored, so it is redelivered).

    {b Business Justification:} Graceful shutdown on SIGTERM (CLAUDE.md 6.1).

    {b Errors:} None.

    {b Side Effects:} sets the flag.

    {b Complexity:} O(1).

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      stop t
    ]}

    {b See Also:} {!close}.

    @param t the consumer.
    @since parser 0.1.0 *)
let stop t = t.stopping <- true

(** Tells whether the consumer polled recently.

    {b Description:} [true] if the last poll ended less than [max_age_s] seconds
    ago. A message retried for longer makes the check fail.

    {b Business Justification:} The [consumer] check of [GET /health].

    {b Errors:} None.

    {b Side Effects:} reads the clock.

    {b Complexity:} O(1).

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      alive t ~max_age_s:15.
    ]}

    {b See Also:} {!Http}.

    @param t the consumer.
    @param max_age_s the maximum age of the last poll.
    @return whether the consumer is alive.
    @since parser 0.1.0 *)
let alive t ~max_age_s = Unix.gettimeofday () -. t.last_poll < max_age_s

(** Tells whether the first broker accepts TCP connections.

    {b Description:} Resolves the first [host:port] of [brokers] and opens (then
    closes) a TCP connection within [timeout_s] seconds.

    {b Business Justification:} The [broker] check of [GET /health]: the
    librdkafka bindings expose no connection state.

    {b Errors:} None; any failure returns [false].

    {b Side Effects:} one DNS lookup and one TCP connection.

    {b Complexity:} O(1).

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      broker_reachable ~brokers:"redpanda:9092" ~timeout_s:1.
    ]}

    {b See Also:} {!Http.health}.

    @param brokers comma-separated [host:port] list.
    @param timeout_s the time limit.
    @return a promise of whether the broker is reachable.
    @since parser 0.1.0 *)
let broker_reachable ~brokers ~timeout_s =
  match
    String.split_on_char ':' (List.hd (String.split_on_char ',' brokers))
  with
  | [ host; port ] ->
      Lwt.catch
        (fun () ->
          Lwt_unix.with_timeout timeout_s (fun () ->
              Lwt.bind
                (Lwt_unix.getaddrinfo host port
                   [ Unix.AI_SOCKTYPE Unix.SOCK_STREAM ]) (function
                | [] -> Lwt.return false
                | address :: _ ->
                    let socket =
                      Lwt_unix.socket address.Unix.ai_family Unix.SOCK_STREAM 0
                    in
                    Lwt.finalize
                      (fun () ->
                        Lwt.map
                          (fun () -> true)
                          (Lwt_unix.connect socket address.Unix.ai_addr))
                      (fun () -> Lwt_unix.close socket))))
        (fun _ -> Lwt.return false)
  | _ -> Lwt.return false

(** Stops consumption and releases the Kafka handles.

    {b Description:} Stops every partition (committing the stored offsets),
    destroys the queue, the input topic and the consumer, waits up to [flush_s]
    seconds for outstanding deliveries, and destroys the output topic and the
    producer. The queue must be destroyed before the consumer, or librdkafka
    waits for it forever.

    {b Business Justification:} Graceful shutdown within 10 s (CLAUDE.md 6.1).

    {b Errors:} None.

    {b Side Effects:} network calls to commit offsets; closes connections.

    {b Complexity:} O(p) in the number of partitions.

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      close t ~flush_s:2.
    ]}

    {b See Also:} {!stop}.

    @param t the stopped consumer.
    @param flush_s the maximum wait for outstanding deliveries.
    @return a promise resolved when everything is released.
    @since parser 0.1.0 *)
let close t ~flush_s =
  List.iter (fun p -> Kafka.consume_stop t.input p) t.partitions;
  Kafka.destroy_queue t.queue;
  Kafka.destroy_topic t.input;
  Kafka.destroy_handler t.consumer;
  Lwt.bind
    (Lwt.pick [ Kafka_lwt.wait_delivery t.producer; Lwt_unix.sleep flush_s ])
    (fun () ->
      Kafka.destroy_topic t.output;
      Kafka.destroy_handler t.producer;
      Lwt.return_unit)
