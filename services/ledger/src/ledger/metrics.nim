# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          ledger/metrics
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         In-process Prometheus metrics of the ledger and their
#                  text exposition.
# Related Docs:    CLAUDE.md 6.1, services/ledger/docs/API.md (Metrics),
#                  services/ledger/docs/SLO.md

## Prometheus metrics.
##
## **Description:** A small registry of counters and gauges with at most
## one label, rendered in the Prometheus text format 0.0.4. Metric names
## are prefixed `ledger_` (CLAUDE.md 2: the service name is the metric
## prefix). No client library exists for Nim in the standard library, and
## the handful of series below does not justify one.
##
## **Business Justification:** `GET /metrics` (CLAUDE.md 6.1) feeds the
## dashboards and alerts of phase 7.
##
## **Thread Safety:** not thread-safe; used from the event loop only.
##
## **Owner:** Transaction Integrity Office (TIO).
##
## **Since:** ledger 0.1.0

import std/[algorithm, strutils, tables]

type
  Kind* = enum
    ## Type of a metric family.
    ##
    ## **Description:** The `# TYPE` of the exposition format.
    ##
    ## **Business Justification:** Prometheus needs the type.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    mkCounter = "counter" ## Monotonic total.
    mkGauge = "gauge" ## Value that goes up and down.

  Family = object
    ## One metric family: help text, type, label name and series.
    ##
    ## **Description:** Series are keyed by label value (empty without a
    ## label).
    ##
    ## **Business Justification:** Internal storage of `Registry`.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    help: string ## `# HELP` text.
    kind: Kind ## `# TYPE`.
    label: string ## Label name, or empty.
    series: OrderedTable[string, float] ## Value per label value.

  Registry* = ref object
    ## The metrics of one process.
    ##
    ## **Description:** Families in registration order.
    ##
    ## **Business Justification:** One registry per process, passed
    ## explicitly.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    families: OrderedTable[string, Family] ## Families by full name.

proc newRegistry*(): Registry =
  ## An empty registry.
  ##
  ## **Description:** Families are added with `register`.
  ##
  ## **Business Justification:** The process registry.
  ##
  ## **Returns:** the registry.
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
  runnableExamples:
    doAssert newRegistry().render() == ""
  Registry()

proc register*(r: Registry, name, help: string, kind: Kind, label = "") =
  ## Declares a metric family.
  ##
  ## **Description:** A family without a label starts with one series at
  ## 0, so that it is exported before its first event.
  ##
  ## **Business Justification:** Every metric is documented by its help
  ## text.
  ##
  ## **Parameters:**
  ## - `r`: the registry.
  ## - `name`: full metric name (`ledger_...`).
  ## - `help`: help text.
  ## - `kind`: counter or gauge.
  ## - `label`: label name, or empty.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None (registering again replaces the family).
  ##
  ## **Side Effects:** mutates the registry.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  runnableExamples:
    import std/strutils
    let r = newRegistry()
    r.register("ledger_up", "Up.", mkGauge)
    doAssert "ledger_up 0" in r.render()
  var f = Family(help: help, kind: kind, label: label)
  if label.len == 0:
    f.series[""] = 0
  r.families[name] = f

proc add*(r: Registry, name: string, delta: float = 1, labelValue = "") =
  ## Adds `delta` to a series.
  ##
  ## **Description:** Creates the series on first use. Unknown families are
  ## ignored, so that a typo cannot crash the service.
  ##
  ## **Business Justification:** Counting events.
  ##
  ## **Parameters:**
  ## - `r`: the registry.
  ## - `name`: the family.
  ## - `delta`: the increment (counters: not negative).
  ## - `labelValue`: the label value, or empty.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** mutates the registry.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  runnableExamples:
    import std/strutils
    let r = newRegistry()
    r.register("ledger_x_total", "X.", mkCounter, "outcome")
    r.add("ledger_x_total", 1, "ok")
    doAssert "ledger_x_total{outcome=\"ok\"} 1" in r.render()
  if name notin r.families:
    return
  r.families[name].series.mgetOrPut(labelValue, 0) += delta

proc set*(r: Registry, name: string, value: float, labelValue = "") =
  ## Sets a gauge series.
  ##
  ## **Description:** Creates the series on first use; unknown families are
  ## ignored.
  ##
  ## **Business Justification:** Current values (active tasks).
  ##
  ## **Parameters:**
  ## - `r`: the registry.
  ## - `name`: the family.
  ## - `value`: the new value.
  ## - `labelValue`: the label value, or empty.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** mutates the registry.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  runnableExamples:
    import std/strutils
    let r = newRegistry()
    r.register("ledger_g", "G.", mkGauge)
    r.set("ledger_g", 3)
    doAssert "ledger_g 3" in r.render()
  if name notin r.families:
    return
  r.families[name].series[labelValue] = value

proc formatValue(v: float): string =
  ## A sample value: integers without a fraction.
  ##
  ## **Description:** `3.0` → `3`, `0.25` → `0.25`.
  ##
  ## **Business Justification:** Readable exposition.
  ##
  ## **Parameters:**
  ## - `v`: the value.
  ##
  ## **Returns:** the text.
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
  if v == float(int64(v)): $int64(v) else: $v

proc render*(r: Registry): string =
  ## The text exposition of every family.
  ##
  ## **Description:** `# HELP`, `# TYPE`, then the series sorted by label
  ## value; a labelled family without series shows only its comments.
  ##
  ## **Business Justification:** The body of `GET /metrics`.
  ##
  ## **Parameters:**
  ## - `r`: the registry.
  ##
  ## **Returns:** the exposition text.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(s log s) for s series.
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  runnableExamples:
    import std/strutils
    let r = newRegistry()
    r.register("ledger_up", "Whether the process runs.", mkGauge)
    doAssert r.render().startsWith("# HELP ledger_up Whether the process runs.\n")
  for name, f in r.families:
    result.add("# HELP " & name & " " & f.help & "\n")
    result.add("# TYPE " & name & " " & $f.kind & "\n")
    var keys: seq[string]
    for k in f.series.keys:
      keys.add(k)
    keys.sort()
    for k in keys:
      let labels = if f.label.len == 0: "" else: "{" & f.label & "=\"" &
          k.replace("\\", "\\\\").replace("\"", "\\\"") & "\"}"
      result.add(name & labels & " " & formatValue(f.series[k]) & "\n")
