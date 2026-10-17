# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          config.nims
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         Compiler settings shared by every build, test, lint and
#                  documentation run of the ledger.
# Related Docs:    services/ledger/Dockerfile, ADR-0017

# `checksums` (SHA-256) ships with the Nim distribution in dist/, which is not
# on the default search path; it is found next to the running compiler.
import std/os
switch("path", selfExe().parentDir.parentDir / "dist" / "checksums" / "src")
switch("path", thisDir() & "/src")
# Identifiers must be spelled like their declarations (NEP1 consistency).
switch("styleCheck", "error")
# Hints are noise in builds; the lint stage defines `lintHints` to keep them
# and turn on the unused-declaration hint.
if not defined(lintHints):
  switch("hints", "off")
# One async event loop and no Nim threads (librdkafka's own threads never call
# into Nim, ADR-0017): without threads the GC-safety analysis does not apply
# to the event-loop globals of ledger/kafka.
switch("threads", "off")
