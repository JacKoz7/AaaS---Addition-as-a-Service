# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          ledger/kafka
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         Kafka consumer and producer of the ledger over the C API of
#                  librdkafka (Nim FFI).
# Related Docs:    ADR-0017, librdkafka rdkafka.h, CLAUDE.md 4.2 and 6.1

## Kafka (Redpanda) access through librdkafka.
##
## **Description:** Nim has no maintained Kafka client; librdkafka's C API
## is imported directly (ADR-0017). Every callback of librdkafka (delivery
## reports, errors, statistics and, with `log.queue=true`, log lines) is
## served by `rd_kafka_poll` / `rd_kafka_consumer_poll`, which this module
## calls only from the event loop thread with a zero timeout. Callbacks
## therefore run in the Nim thread and may touch Nim objects; librdkafka's
## internal threads never call into Nim.
##
## - **Consumer:** consumer group, manual offset commits (after the event
##   is stored), `auto.offset.reset=earliest`.
## - **Producer:** idempotent, `acks=all`; `publish` returns a future that
##   completes with the broker's delivery report.
## - **Health:** `statistics.interval.ms=5000`; a handle is connected when
##   its last statistics report at least one known broker in state `UP`.
##
## **Business Justification:** The ledger consumes additions and announces
## recorded results on the event bus (CLAUDE.md 4.2).
##
## **Thread Safety:** not thread-safe; event loop only.
##
## **Owner:** Transaction Integrity Office (TIO).
##
## **Since:** ledger 0.1.0

import std/[asyncdispatch, json, options, tables]
import logging

{.passl: "-lrdkafka".}
# The callbacks below are declared with `cstring` and `ptr RdKafka`, which
# Nim emits as `char *` and `rd_kafka_t *`; librdkafka declares some of them
# with `const` parameters. The types differ only in const qualification,
# which GCC 15 reports as an error; this module's C file only.
{.localPassC: "-Wno-incompatible-pointer-types".}

const rdh = "<librdkafka/rdkafka.h>"
  ## The C header of librdkafka.
  ##
  ## **Description:** Installed by the `librdkafka-dev` package.
  ##
  ## **Business Justification:** Every import below names it.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0

type
  RdKafka {.importc: "rd_kafka_t", header: rdh, incompleteStruct.} = object
    ## A librdkafka client handle (opaque).
  RdConf {.importc: "rd_kafka_conf_t", header: rdh, incompleteStruct.} = object
    ## A librdkafka configuration (opaque).
  RdTopic {.importc: "rd_kafka_topic_t", header: rdh, incompleteStruct.} = object
    ## A librdkafka topic handle (opaque).
  RdPartitionList {.importc: "rd_kafka_topic_partition_list_t", header: rdh,
      incompleteStruct.} = object
    ## A librdkafka list of topic partitions (opaque here).
  RdMessage {.importc: "rd_kafka_message_t", header: rdh.} = object
    ## A consumed message or a delivery report (`rd_kafka_message_t`).
    err: cint                               ## Error code, 0 for none.
    rkt: ptr RdTopic                        ## Topic handle.
    partition: int32                        ## Partition.
    payload: pointer                        ## Value bytes.
    len: csize_t                            ## Value length.
    key: pointer                            ## Key bytes.
    keyLen {.importc: "key_len".}: csize_t  ## Key length.
    offset: int64                           ## Offset.
    opaque {.importc: "_private".}: pointer ## Per-message opaque of produce.

  DeliveryCallback = proc(rk: ptr RdKafka, msg: ptr RdMessage,
      opaque: pointer) {.cdecl.}
    ## `dr_msg_cb` of librdkafka: one delivery report per produced message.
    ##
    ## **Description:** Served by `rd_kafka_poll`; `msg.opaque` is the per-message opaque.
    ##
    ## **Business Justification:** Completes the futures of `publish`.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
  ErrorCallback = proc(rk: ptr RdKafka, err: cint, reason: cstring,
      opaque: pointer) {.cdecl.}
    ## `error_cb` of librdkafka: a client-level error.
    ##
    ## **Description:** Served by the poll functions.
    ##
    ## **Business Justification:** Broker problems are logged.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
  LogCallback = proc(rk: ptr RdKafka, level: cint, fac,
      buf: cstring) {.cdecl.}
    ## `log_cb` of librdkafka: one log line.
    ##
    ## **Description:** Served by the poll functions because of `log.queue=true`.
    ##
    ## **Business Justification:** librdkafka logs become JSON log lines.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
  StatsCallback = proc(rk: ptr RdKafka, json: cstring, len: csize_t,
      opaque: pointer): cint {.cdecl.}
    ## `stats_cb` of librdkafka: the statistics JSON document.
    ##
    ## **Description:** Served by the poll functions every `statistics.interval.ms`.
    ##
    ## **Business Justification:** Feeds the `broker` health check.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

proc rdConfNew(): ptr RdConf {.importc: "rd_kafka_conf_new", header: rdh.}
  ## `rd_kafka_conf_new`.
proc rdConfSet(conf: ptr RdConf, name, value: cstring, errstr: cstring,
    size: csize_t): cint {.importc: "rd_kafka_conf_set", header: rdh.}
  ## `rd_kafka_conf_set`; 0 is `RD_KAFKA_CONF_OK`.
proc rdConfSetDrMsgCb(conf: ptr RdConf, cb: DeliveryCallback) {.
    importc: "rd_kafka_conf_set_dr_msg_cb", header: rdh.}
  ## `rd_kafka_conf_set_dr_msg_cb`.
proc rdConfSetErrorCb(conf: ptr RdConf, cb: ErrorCallback) {.
    importc: "rd_kafka_conf_set_error_cb", header: rdh.}
  ## `rd_kafka_conf_set_error_cb`.
proc rdConfSetLogCb(conf: ptr RdConf, cb: LogCallback) {.
    importc: "rd_kafka_conf_set_log_cb", header: rdh.}
  ## `rd_kafka_conf_set_log_cb`.
proc rdConfSetStatsCb(conf: ptr RdConf, cb: StatsCallback) {.
    importc: "rd_kafka_conf_set_stats_cb", header: rdh.}
  ## `rd_kafka_conf_set_stats_cb`.
proc rdNew(kind: cint, conf: ptr RdConf, errstr: cstring,
    size: csize_t): ptr RdKafka {.importc: "rd_kafka_new", header: rdh.}
  ## `rd_kafka_new`; takes ownership of `conf` on success.
proc rdSetLogQueue(rk: ptr RdKafka, queue: pointer): cint {.
    importc: "rd_kafka_set_log_queue", header: rdh.}
  ## `rd_kafka_set_log_queue`; `nil` forwards logs to the main queue.
proc rdPollSetConsumer(rk: ptr RdKafka): cint {.
    importc: "rd_kafka_poll_set_consumer", header: rdh.}
  ## `rd_kafka_poll_set_consumer`.
proc rdListNew(size: cint): ptr RdPartitionList {.
    importc: "rd_kafka_topic_partition_list_new", header: rdh.}
  ## `rd_kafka_topic_partition_list_new`.
proc rdListAdd(list: ptr RdPartitionList, topic: cstring,
    partition: int32): pointer {.
    importc: "rd_kafka_topic_partition_list_add", header: rdh.}
  ## `rd_kafka_topic_partition_list_add`.
proc rdListDestroy(list: ptr RdPartitionList) {.
    importc: "rd_kafka_topic_partition_list_destroy", header: rdh.}
  ## `rd_kafka_topic_partition_list_destroy`.
proc rdSubscribe(rk: ptr RdKafka, list: ptr RdPartitionList): cint {.
    importc: "rd_kafka_subscribe", header: rdh.}
  ## `rd_kafka_subscribe`.
proc rdConsumerPoll(rk: ptr RdKafka, timeoutMs: cint): ptr RdMessage {.
    importc: "rd_kafka_consumer_poll", header: rdh.}
  ## `rd_kafka_consumer_poll`.
proc rdMessageDestroy(msg: ptr RdMessage) {.
    importc: "rd_kafka_message_destroy", header: rdh.}
  ## `rd_kafka_message_destroy`.
proc rdCommitMessage(rk: ptr RdKafka, msg: ptr RdMessage, async: cint): cint {.
    importc: "rd_kafka_commit_message", header: rdh.}
  ## `rd_kafka_commit_message`.
proc rdConsumerClose(rk: ptr RdKafka): cint {.
    importc: "rd_kafka_consumer_close", header: rdh.}
  ## `rd_kafka_consumer_close`.
proc rdDestroy(rk: ptr RdKafka) {.importc: "rd_kafka_destroy", header: rdh.}
  ## `rd_kafka_destroy`.
proc rdTopicNew(rk: ptr RdKafka, topic: cstring, conf: pointer): ptr RdTopic {.
    importc: "rd_kafka_topic_new", header: rdh.}
  ## `rd_kafka_topic_new`.
proc rdTopicDestroy(rkt: ptr RdTopic) {.importc: "rd_kafka_topic_destroy",
    header: rdh.}
  ## `rd_kafka_topic_destroy`.
proc rdProduce(rkt: ptr RdTopic, partition: int32, flags: cint,
    payload: pointer, len: csize_t, key: pointer, keyLen: csize_t,
    opaque: pointer): cint {.importc: "rd_kafka_produce", header: rdh.}
  ## `rd_kafka_produce`; -1 on failure (see `rd_kafka_last_error`).
proc rdPoll(rk: ptr RdKafka, timeoutMs: cint): cint {.importc: "rd_kafka_poll",
    header: rdh.}
  ## `rd_kafka_poll`.
proc rdFlush(rk: ptr RdKafka, timeoutMs: cint): cint {.
    importc: "rd_kafka_flush", header: rdh.}
  ## `rd_kafka_flush`.
proc rdErr2Str(err: cint): cstring {.importc: "rd_kafka_err2str", header: rdh.}
  ## `rd_kafka_err2str`.
proc rdLastError(): cint {.importc: "rd_kafka_last_error", header: rdh.}
  ## `rd_kafka_last_error`.
proc rdName(rk: ptr RdKafka): cstring {.importc: "rd_kafka_name", header: rdh.}
  ## `rd_kafka_name`: the client instance name.

const
  partitionUnassigned = -1'i32
    ## `RD_KAFKA_PARTITION_UA`: let the partitioner choose by key.
    ##
    ## **Description:** Keyed messages go to the partition of their key.
    ##
    ## **Business Justification:** Partitioning by `taskId` (CLAUDE.md 4.2).
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
  msgFlagCopy = 2'i32
    ## `RD_KAFKA_MSG_F_COPY`: librdkafka copies the payload.
    ##
    ## **Description:** The Nim string may be freed after `publish`.
    ##
    ## **Business Justification:** Memory safety across the FFI.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

type
  KafkaError* = object of CatchableError
    ## A librdkafka call or a delivery failed.
    ##
    ## **Description:** The message is librdkafka's error string.
    ##
    ## **Business Justification:** Callers retry publications.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

  KafkaMessage* = object
    ## A consumed message, copied out of librdkafka.
    ##
    ## **Description:** `handle` stays valid until `commit` or `release`.
    ##
    ## **Business Justification:** Nim strings for the decoder.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    partition*: int32 ## Partition of the message.
    offset*: int64 ## Offset of the message.
    key*: string ## Key (the taskId).
    value*: string ## Value (the event JSON).
    handle: ptr RdMessage ## The librdkafka message.

  Client = object
    ## State shared with the callbacks, per librdkafka handle.
    ##
    ## **Description:** Keyed by the handle's instance name.
    ##
    ## **Business Justification:** C callbacks cannot capture Nim closures.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    logger: Logger ## Where librdkafka's log lines go.
    connected: bool ## Last statistics showed a broker `UP`.

  KafkaConsumer* = ref object
    ## A consumer group member subscribed to one topic.
    ##
    ## **Description:** Built by `newConsumer`.
    ##
    ## **Business Justification:** Consumes `aaas.addition.requested.v1`.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    rk: ptr RdKafka ## The handle.
    name: string ## Instance name (key of `clients`).

  KafkaProducer* = ref object
    ## An idempotent producer.
    ##
    ## **Description:** Built by `newProducer`.
    ##
    ## **Business Justification:** Publishes `aaas.ledger.appended.v1`.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    rk: ptr RdKafka ## The handle.
    name: string ## Instance name (key of `clients`).
    topics: Table[string, ptr RdTopic] ## Topic handles by name.

var
  clients: Table[string, Client]
    ## Callback state by instance name.
    ##
    ## **Description:** Written by `newHandle`, read by the callbacks; event loop only.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
  pending: Table[int, Future[void]]
    ## Deliveries awaited by `publish`, by message id.
    ##
    ## **Description:** An entry is removed by its delivery report.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
  nextMessageId = 1
    ## Id of the next produced message.
    ##
    ## **Description:** Passed to librdkafka as the per-message opaque; never 0.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

proc levelOf(syslog: cint): Level =
  ## Maps a syslog level of librdkafka (0..7) to a log level.
  ##
  ## **Description:** 0..3 error, 4 warn, 5..6 info, 7 debug.
  ##
  ## **Business Justification:** librdkafka logs become JSON log lines.
  ##
  ## **Parameters:**
  ## - `syslog`: the level.
  ##
  ## **Returns:** the level.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  if syslog <= 3: lvError elif syslog == 4: lvWarn elif syslog <= 6: lvInfo else: lvDebug

proc onLog(rk: ptr RdKafka, level: cint, fac, buf: cstring) {.cdecl.} =
  ## `log_cb`: writes a librdkafka log line as a JSON log line.
  ##
  ## **Description:** Runs in the event loop thread (`log.queue=true`).
  ##
  ## **Business Justification:** One log format (CLAUDE.md 6.1).
  ##
  ## **Parameters:** those of `log_cb`.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** one log line.
  ##
  ## **Complexity:** O(size of the line).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  let name = $rdName(rk)
  if name in clients:
    clients[name].logger.log(levelOf(level), "librdkafka: " & $buf,
        extra = [("facility", %($fac)), ("client", %name)])

proc onError(rk: ptr RdKafka, err: cint, reason: cstring,
    opaque: pointer) {.cdecl.} =
  ## `error_cb`: logs a client-level error.
  ##
  ## **Description:** librdkafka recovers from these by itself; an
  ## unreachable broker also shows in the statistics.
  ##
  ## **Business Justification:** Visible broker problems.
  ##
  ## **Parameters:** those of `error_cb`.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** one log line.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  let name = $rdName(rk)
  if name in clients:
    clients[name].logger.log(lvWarn, "kafka error: " & $reason,
        extra = [("code", %err), ("client", %name)])

proc brokerUp*(stats: string): bool =
  ## Whether librdkafka statistics show a known broker in state `UP`.
  ##
  ## **Description:** Bootstrap entries (`nodeid` -1) are ignored; a
  ## malformed document counts as down.
  ##
  ## **Business Justification:** The `broker` health check.
  ##
  ## **Parameters:**
  ## - `stats`: the statistics JSON of `stats_cb`.
  ##
  ## **Returns:** `true` if connected.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(size of the document).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  runnableExamples:
    doAssert brokerUp("""{"brokers":{"redpanda:9092/0":{"nodeid":0,"state":"UP"}}}""")
    doAssert not brokerUp("""{"brokers":{"redpanda:9092/bootstrap":{"nodeid":-1,"state":"UP"}}}""")
    doAssert not brokerUp("not json")
  try:
    let node = parseJson(stats)
    for _, b in node{"brokers"}.getFields:
      if b{"nodeid"}.getInt(-1) >= 0 and b{"state"}.getStr == "UP":
        return true
  except CatchableError:
    discard
  false

proc onStats(rk: ptr RdKafka, json: cstring, len: csize_t,
    opaque: pointer): cint {.cdecl.} =
  ## `stats_cb`: records whether the handle is connected.
  ##
  ## **Description:** Returns 0, so librdkafka frees the document.
  ##
  ## **Business Justification:** The `broker` health check.
  ##
  ## **Parameters:** those of `stats_cb`.
  ##
  ## **Returns:** 0.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** updates the client state.
  ##
  ## **Complexity:** O(size of the document).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  let name = $rdName(rk)
  if name in clients:
    clients[name].connected = brokerUp($json)
  0

proc onDelivery(rk: ptr RdKafka, msg: ptr RdMessage, opaque: pointer) {.cdecl.} =
  ## `dr_msg_cb`: completes or fails the future of the delivered message.
  ##
  ## **Description:** The message id travels as the per-message opaque.
  ##
  ## **Business Justification:** `publish` waits for the acknowledgement.
  ##
  ## **Parameters:** those of `dr_msg_cb`.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** completes a future.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  let id = cast[int](msg.opaque)
  var fut: Future[void]
  if pending.pop(id, fut):
    if msg.err == 0:
      fut.complete()
    else:
      fut.fail(newException(KafkaError, $rdErr2Str(msg.err)))

proc newConf(settings: openArray[(string, string)]): ptr RdConf =
  ## A configuration with the common callbacks and `settings`.
  ##
  ## **Description:** Sets `log.queue=true` and the log, error and
  ## statistics callbacks.
  ##
  ## **Business Justification:** Shared by consumer and producer.
  ##
  ## **Parameters:**
  ## - `settings`: librdkafka properties.
  ##
  ## **Returns:** the configuration.
  ##
  ## **Errors:** `KafkaError` for an invalid property.
  ##
  ## **Side Effects:** allocates C memory (owned by `rd_kafka_new`).
  ##
  ## **Complexity:** O(number of settings).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  result = rdConfNew()
  var err = newString(512)
  for (k, v) in @[("log.queue", "true"), ("statistics.interval.ms", "5000")] & @settings:
    if rdConfSet(result, k.cstring, v.cstring, err.cstring, 512) != 0:
      raise newException(KafkaError, k & ": " & $err.cstring)
  rdConfSetLogCb(result, onLog)
  rdConfSetErrorCb(result, onError)
  rdConfSetStatsCb(result, onStats)

proc newHandle(kind: cint, conf: ptr RdConf, logger: Logger): (ptr RdKafka, string) =
  ## Creates a handle and registers its callback state.
  ##
  ## **Description:** Forwards logs to the main queue.
  ##
  ## **Business Justification:** Shared by consumer and producer.
  ##
  ## **Parameters:**
  ## - `kind`: 0 producer, 1 consumer.
  ## - `conf`: the configuration.
  ## - `logger`: for librdkafka's logs.
  ##
  ## **Returns:** the handle and its instance name.
  ##
  ## **Errors:** `KafkaError` if librdkafka refuses the configuration.
  ##
  ## **Side Effects:** starts librdkafka's threads.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  var err = newString(512)
  let rk = rdNew(kind, conf, err.cstring, 512)
  if rk == nil:
    raise newException(KafkaError, $err.cstring)
  discard rdSetLogQueue(rk, nil)
  let name = $rdName(rk)
  clients[name] = Client(logger: logger, connected: false)
  (rk, name)

proc newConsumer*(brokers, group, topic, clientId: string, logLevel: int,
    logger: Logger): KafkaConsumer =
  ## A consumer subscribed to `topic`.
  ##
  ## **Description:** Manual commits, earliest offset for a new group.
  ##
  ## **Business Justification:** See the module documentation.
  ##
  ## **Parameters:**
  ## - `brokers`: bootstrap servers.
  ## - `group`: consumer group.
  ## - `topic`: the topic.
  ## - `clientId`: the client id.
  ## - `logLevel`: librdkafka log level 0..7.
  ## - `logger`: for librdkafka's logs.
  ##
  ## **Returns:** the consumer.
  ##
  ## **Errors:** `KafkaError` for a rejected configuration or
  ## subscription.
  ##
  ## **Side Effects:** connects to the brokers in the background.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `let c = newConsumer("redpanda:9092", "ledger", requestedTopic, "ledger", 4, logger)`.
  let conf = newConf([("bootstrap.servers", brokers), ("group.id", group),
      ("client.id", clientId), ("enable.auto.commit", "false"),
      ("auto.offset.reset", "earliest"), ("log_level", $logLevel)])
  let (rk, name) = newHandle(1, conf, logger)
  discard rdPollSetConsumer(rk)
  let list = rdListNew(1)
  discard rdListAdd(list, topic.cstring, partitionUnassigned)
  let rc = rdSubscribe(rk, list)
  rdListDestroy(list)
  if rc != 0:
    raise newException(KafkaError, "subscribe " & topic & ": " & $rdErr2Str(rc))
  KafkaConsumer(rk: rk, name: name)

proc copyBytes(p: pointer, n: csize_t): string =
  ## Copies `n` bytes at `p` into a string.
  ##
  ## **Description:** `nil` or zero length gives "".
  ##
  ## **Business Justification:** Messages leave librdkafka's memory.
  ##
  ## **Parameters:**
  ## - `p`: the bytes.
  ## - `n`: their count.
  ##
  ## **Returns:** the string.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(n).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  if p == nil or n == 0:
    return ""
  result = newString(int(n))
  copyMem(addr result[0], p, int(n))

proc poll*(c: KafkaConsumer): Option[KafkaMessage] =
  ## The next message, without waiting.
  ##
  ## **Description:** Also serves the callbacks of the consumer. Errors
  ## carried as messages (no message, partition end, broker events) are
  ## logged by `error_cb` or ignored.
  ##
  ## **Business Justification:** Called by the consume loop.
  ##
  ## **Parameters:**
  ## - `c`: the consumer.
  ##
  ## **Returns:** a message, or `none`.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** serves callbacks.
  ##
  ## **Complexity:** O(size of the message).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `let m = consumer.poll(); if m.isSome: consumer.commit(m.get)`.
  let m = rdConsumerPoll(c.rk, 0)
  if m == nil:
    return none(KafkaMessage)
  if m.err != 0:
    let name = c.name
    if name in clients:
      clients[name].logger.log(lvDebug, "consumer event: " & $rdErr2Str(m.err))
    rdMessageDestroy(m)
    return none(KafkaMessage)
  some(KafkaMessage(partition: m.partition, offset: m.offset,
      key: copyBytes(m.key, m.keyLen), value: copyBytes(m.payload, m.len),
      handle: m))

proc commit*(c: KafkaConsumer, msg: KafkaMessage) =
  ## Commits the offset after `msg` and releases it.
  ##
  ## **Description:** Asynchronous commit: a commit lost in a crash only
  ## redelivers the message, which the idempotent consumer ignores.
  ##
  ## **Business Justification:** Offsets advance only after the event is
  ## stored.
  ##
  ## **Parameters:**
  ## - `c`: the consumer.
  ## - `msg`: a message of `poll`, not yet committed or released.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None (a failed commit is logged by librdkafka).
  ##
  ## **Side Effects:** an offset commit request.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `consumer.commit(msg)` after the event is stored.
  discard rdCommitMessage(c.rk, msg.handle, 1)
  rdMessageDestroy(msg.handle)

proc release*(msg: KafkaMessage) =
  ## Releases a message without committing it.
  ##
  ## **Description:** The message is delivered again after a restart or a
  ## rebalance.
  ##
  ## **Business Justification:** Shutdown while a message is in process.
  ##
  ## **Parameters:**
  ## - `msg`: a message of `poll`.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** frees librdkafka memory.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `release(msg)` when shutting down before the event is stored.
  rdMessageDestroy(msg.handle)

proc connected*(c: KafkaConsumer): bool =
  ## Whether the consumer's last statistics showed a broker `UP`.
  ##
  ## **Description:** False until the first statistics (5 s).
  ##
  ## **Business Justification:** The `broker` health check.
  ##
  ## **Parameters:**
  ## - `c`: the consumer.
  ##
  ## **Returns:** the state.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `Health(checks: @[("broker", consumer.connected)])`.
  c.name in clients and clients[c.name].connected

proc close*(c: KafkaConsumer) =
  ## Leaves the group and destroys the consumer.
  ##
  ## **Description:** Pending asynchronous commits are sent first.
  ##
  ## **Business Justification:** Graceful shutdown: the group rebalances
  ## at once instead of after the session timeout.
  ##
  ## **Parameters:**
  ## - `c`: the consumer.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** network round trips; frees the handle.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `consumer.close()` during shutdown.
  discard rdConsumerClose(c.rk)
  rdDestroy(c.rk)
  clients.del(c.name)

proc newProducer*(brokers, clientId: string, logLevel: int,
    logger: Logger): KafkaProducer =
  ## An idempotent producer.
  ##
  ## **Description:** `acks=all`, `enable.idempotence=true`, messages
  ## expire after 5 s without acknowledgement, `linger.ms=5`.
  ##
  ## **Business Justification:** See the module documentation.
  ##
  ## **Parameters:**
  ## - `brokers`: bootstrap servers.
  ## - `clientId`: the client id.
  ## - `logLevel`: librdkafka log level 0..7.
  ## - `logger`: for librdkafka's logs.
  ##
  ## **Returns:** the producer.
  ##
  ## **Errors:** `KafkaError` for a rejected configuration.
  ##
  ## **Side Effects:** connects to the brokers in the background.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `let p = newProducer("redpanda:9092", "ledger", 4, logger)`.
  let conf = newConf([("bootstrap.servers", brokers), ("client.id", clientId),
      ("acks", "all"), ("enable.idempotence", "true"),
      ("message.timeout.ms", "5000"), ("linger.ms", "5"),
      ("log_level", $logLevel)])
  rdConfSetDrMsgCb(conf, onDelivery)
  let (rk, name) = newHandle(0, conf, logger)
  KafkaProducer(rk: rk, name: name)

proc publish*(p: KafkaProducer, topic, key, value: string): Future[void] =
  ## Sends a message and completes when the broker acknowledged it.
  ##
  ## **Description:** The future fails with `KafkaError` if librdkafka
  ## refuses the message or its delivery fails (including the 5 s message
  ## timeout). `serve` must run for the future to complete.
  ##
  ## **Business Justification:** The ledger records a publication only
  ## after the acknowledgement.
  ##
  ## **Parameters:**
  ## - `p`: the producer.
  ## - `topic`: the topic.
  ## - `key`: the key (the taskId).
  ## - `value`: the event JSON.
  ##
  ## **Returns:** the delivery future.
  ##
  ## **Errors:** see Description.
  ##
  ## **Side Effects:** one message.
  ##
  ## **Complexity:** O(size of the message).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `await producer.publish(appendedTopic, taskId, event)`.
  result = newFuture[void]("kafka.publish")
  if topic notin p.topics:
    p.topics[topic] = rdTopicNew(p.rk, topic.cstring, nil)
  let id = nextMessageId
  inc nextMessageId
  pending[id] = result
  let rc = rdProduce(p.topics[topic], partitionUnassigned, msgFlagCopy,
      (if value.len > 0: unsafeAddr value[0] else: nil), csize_t(value.len),
      (if key.len > 0: unsafeAddr key[0] else: nil), csize_t(key.len),
      cast[pointer](id))
  if rc != 0:
    pending.del(id)
    result.fail(newException(KafkaError, $rdErr2Str(rdLastError())))

proc serve*(p: KafkaProducer) =
  ## Serves the producer's callbacks (delivery reports, logs, statistics).
  ##
  ## **Description:** Non-blocking `rd_kafka_poll`.
  ##
  ## **Business Justification:** Completes the futures of `publish`.
  ##
  ## **Parameters:**
  ## - `p`: the producer.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** runs callbacks.
  ##
  ## **Complexity:** O(number of events served).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `while running: producer.serve(); await sleepAsync(10)`.
  discard rdPoll(p.rk, 0)

proc connected*(p: KafkaProducer): bool =
  ## Whether the producer's last statistics showed a broker `UP`.
  ##
  ## **Description:** False until the first statistics (5 s).
  ##
  ## **Business Justification:** The `broker` health check.
  ##
  ## **Parameters:**
  ## - `p`: the producer.
  ##
  ## **Returns:** the state.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `Health(checks: @[("broker", consumer.connected)])`.
  p.name in clients and clients[p.name].connected

proc close*(p: KafkaProducer, timeoutMs = 2000) =
  ## Flushes outstanding messages and destroys the producer.
  ##
  ## **Description:** Waits up to `timeoutMs` for the flush.
  ##
  ## **Business Justification:** Graceful shutdown.
  ##
  ## **Parameters:**
  ## - `p`: the producer.
  ## - `timeoutMs`: flush deadline.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** network round trips; frees the handle.
  ##
  ## **Complexity:** O(outstanding messages).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `consumer.close()` during shutdown.
  discard rdFlush(p.rk, cint(timeoutMs))
  for _, t in p.topics:
    rdTopicDestroy(t)
  rdDestroy(p.rk)
  clients.del(p.name)
