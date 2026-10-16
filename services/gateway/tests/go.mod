// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       gateway
// Module:          tests/go.mod
// Owning Team:     Platform Enablement Guild (PEG)
// Classification:  INTERNAL
// Purpose:         Go module of the gateway tests: unit tests of the edge
//                  plugin (resolved from ../src/edge) and integration tests
//                  of the Traefik configuration.
// Related Docs:    services/gateway/README.md, ADR-0012

module aaas/gateway-tests

go 1.24

require aaas/edge v0.0.0

replace aaas/edge => ../src/edge
