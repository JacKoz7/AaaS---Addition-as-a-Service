# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          tools/doc_coverage
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         Documentation coverage of the ledger: checks the
#                  `nim jsondoc --docInternal` output of every module for the
#                  docstring fields of CLAUDE.md 6.5.3 and fails below 100%.
# Related Docs:    CLAUDE.md 6.5.3 and 6.5.4, ADR-0009, ADR-0017

## Documentation coverage checker.
##
## **Description:** Reads every `*.json` file of a `nim jsondoc
## --docInternal` output directory (one per module, public and private
## symbols) and checks, after removing HTML tags:
##
## - the module documentation: `Description:`, `Business Justification:`,
##   `Owner:`, `Since:`;
## - routines (`proc`, `func`, `method`, `iterator`, `template`, `macro`,
##   `converter`): `Description:`, `Business Justification:`, `Returns:`,
##   `Errors:`, `Side Effects:`, `Complexity:`, `Thread Safety:`, `Owner:`,
##   `Since:`, `Parameters:` when the routine has parameters, and an example
##   (`runnableExamples`, which `nim doc` runs, or `Example:`) when it is
##   exported;
## - types: `Description:`, `Business Justification:`, `Owner:`, `Since:`;
## - constants, `let` and `var`: `Description:`, `Owner:`, `Since:`;
## - bindings of C functions and types (`importc`): a non-empty
##   description naming the C symbol; their contract is the C header.
##
## Prints one line per symbol that misses a field, the coverage per module
## and in total, and exits 1 below 100%.
##
## **Business Justification:** `make doc-coverage` must show 100%
## (CLAUDE.md 6.5.4); Nim has no native coverage tool.
##
## **Thread Safety:** single-threaded program.
##
## **Owner:** Transaction Integrity Office (TIO).
##
## **Since:** ledger 0.1.0

import std/[algorithm, json, os, re, strutils]

const
  routineKinds = ["skProc", "skFunc", "skMethod", "skIterator", "skTemplate",
      "skMacro", "skConverter"]
    ## jsondoc kinds of routines.
    ##
    ## **Description:** Checked with the routine fields.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
  routineFields = ["Description:", "Business Justification:", "Returns:",
      "Errors:", "Side Effects:", "Complexity:", "Thread Safety:", "Owner:",
      "Since:"]
    ## Fields every routine documents.
    ##
    ## **Description:** CLAUDE.md 6.5.3; `Parameters:` and the example are
    ## checked separately.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
  typeFields = ["Description:", "Business Justification:", "Owner:", "Since:"]
    ## Fields every type and the module documentation carry.
    ##
    ## **Description:** CLAUDE.md 6.5.3 for non-routines.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
  valueFields = ["Description:", "Owner:", "Since:"]
    ## Fields every constant and variable carries.
    ##
    ## **Description:** CLAUDE.md 6.5.3 for values.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

proc plain(html: string): string =
  ## The text of rendered documentation without HTML tags.
  ##
  ## **Description:** Tags are removed and the common entities decoded.
  ##
  ## **Business Justification:** Field names are searched in the text.
  ##
  ## **Parameters:**
  ## - `html`: the rendered description.
  ##
  ## **Returns:** the text.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(length of the text).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  runnableExamples:
    doAssert plain("<p><strong>Owner:</strong> x &amp; y</p>") == "Owner: x & y"
  html.replace(re"<[^>]*>", "").multiReplace(("&amp;", "&"), ("&lt;", "<"),
      ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"))

proc hasRunnableExamples*(source: seq[string], line: int): bool =
  ## Whether the declaration at `line` has a `runnableExamples` block.
  ##
  ## **Description:** Scans from the declaration to the next line that
  ## starts in column 0 with neither a space nor a `#`; jsondoc does not
  ## include the examples in the description.
  ##
  ## **Business Justification:** Examples run by `nim doc` count as the
  ## `Example` field.
  ##
  ## **Parameters:**
  ## - `source`: the lines of the module.
  ## - `line`: 0-based line of the declaration.
  ##
  ## **Returns:** `true` if the block exists.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(length of the declaration).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  runnableExamples:
    doAssert hasRunnableExamples(@["proc f*() =", "  runnableExamples:", "    discard"], 0)
    doAssert not hasRunnableExamples(@["proc f*() =", "  discard", "proc g() ="], 0)
  for i in line + 1 ..< source.len:
    let l = source[i]
    if l.len > 0 and l[0] notin {' ', '#'}:
      return false
    if l.strip == "runnableExamples:":
      return true
  false

proc missing*(kind, code, description: string, exported: bool): seq[string] =
  ## The fields a symbol's documentation lacks.
  ##
  ## **Description:** Applies the rules of the module documentation to
  ## one jsondoc entry.
  ##
  ## **Business Justification:** The core of the check, tested by its
  ## examples.
  ##
  ## **Parameters:**
  ## - `kind`: the jsondoc kind (`skProc`, `skType`, ...).
  ## - `code`: the declaration as rendered by jsondoc.
  ## - `description`: the rendered documentation.
  ## - `exported`: whether the symbol is exported.
  ##
  ## **Returns:** the missing field names (empty when complete).
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(length of the description).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  runnableExamples:
    doAssert missing("skConst", "const x = 1", "", false) == @["description"]
    doAssert missing("skProc", "proc f() {.importc: \"f\".}", "f.", false).len == 0
    doAssert "Example" in missing("skProc", "proc f*()",
        "Description: Business Justification: Returns: Errors: Side Effects: Complexity: Thread Safety: Owner: Since:", true)
  let text = plain(description)
  if text.strip.len == 0:
    return @["description"]
  if "importc" in code:
    return @[]
  var fields: seq[string]
  if kind in routineKinds:
    fields = @routineFields
    let open = code.find('(')
    if open >= 0 and open + 1 < code.len and code[open + 1] != ')':
      fields.add("Parameters:")
  elif kind == "skType":
    fields = @typeFields
  else:
    fields = @valueFields
  for f in fields:
    if f notin text:
      result.add(f.strip(chars = {':'}))
  if kind in routineKinds and exported and "Example" notin text:
    result.add("Example")

proc main(): int =
  ## Checks a jsondoc output directory; the exit code.
  ##
  ## **Description:** The directory is the first argument; every `*.json`
  ## file in it and below is a module.
  ##
  ## **Business Justification:** The `doc-coverage` stage of the
  ## Dockerfile.
  ##
  ## **Returns:** 0 at 100%, 1 below, 2 for a usage error.
  ##
  ## **Errors:** None (problems become the exit code).
  ##
  ## **Side Effects:** reads files; prints to stdout.
  ##
  ## **Complexity:** O(total size of the files).
  ##
  ## **Thread Safety:** single-threaded.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  if paramCount() != 1 or not dirExists(paramStr(1)):
    stderr.writeLine("usage: doc_coverage <jsondoc output directory>")
    return 2
  var files: seq[string]
  for f in walkDirRec(paramStr(1)):
    if f.endsWith(".json"):
      files.add(f)
  files.sort()
  var total, documented = 0
  for f in files:
    let doc = parseJson(readFile(f))
    let module = f.relativePath(paramStr(1)).changeFileExt("")
    let source = if fileExists(doc{"orig"}.getStr): readFile(doc{"orig"}.getStr).splitLines else: @[]
    var count = 1
    var ok = 0
    var gaps = missing("skType", "", doc{"moduleDescription"}.getStr, false)
    if gaps.len == 0:
      inc ok
    else:
      echo module, ": module documentation lacks ", gaps.join(", ")
    for e in doc{"entries"}:
      inc count
      let name = e{"name"}.getStr
      let code = e{"code"}.getStr
      # jsondoc drops the export marker; read it from the declaration line.
      let line = e{"line"}.getInt - 1
      let decl = if line >= 0 and line < source.len: source[line] else: ""
      let exported = name & "*" in decl or "`" & name & "`*" in decl
      var description = e{"description"}.getStr
      if hasRunnableExamples(source, line):
        description.add(" Example")
      gaps = missing(e{"type"}.getStr, code, description, exported)
      if gaps.len == 0:
        inc ok
      else:
        echo module, ".", name, " (line ", e{"line"}.getInt, "): lacks ", gaps.join(", ")
    echo module.alignLeft(28), ($ok & "/" & $count).align(10), "  ",
        formatFloat(100 * ok / count, ffDecimal, 1), "%"
    total += count
    documented += ok
  if total == 0:
    echo "no modules found"
    return 1
  echo "TOTAL".alignLeft(28), ($documented & "/" & $total).align(10), "  ",
      formatFloat(100 * documented / total, ffDecimal, 1), "%"
  if documented == total: 0 else: 1

when isMainModule:
  quit(main())
