// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       gateway
// Module:          src/edge/go.mod
// Owning Team:     Platform Enablement Guild (PEG)
// Classification:  INTERNAL
// Purpose:         Go module of the edge Traefik plugin. The module path is
//                  the moduleName of experimental.localPlugins in
//                  config/traefik.yml; the plugin uses the standard library
//                  only, as Traefik's Yaegi interpreter requires.
// Related Docs:    services/gateway/README.md, ADR-0012

module aaas/edge

go 1.24
