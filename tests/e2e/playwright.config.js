// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       e2e
// Module:          tests/e2e/playwright.config.js
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Playwright configuration of the end-to-end tests: one
//                  headless Chromium against the gateway, reports in
//                  /results.
// Related Docs:    tests/e2e/README.md, CLAUDE.md 6.4, ADR-0019

/**
 * Playwright configuration.
 *
 * Description: The base URL comes from `AAAS_BASE_URL` (default
 * `http://gateway:8000/`, the gateway seen from the `aaas-public` network,
 * where `scripts/e2e.sh` runs the tests). Tests run one at a time
 * (`workers: 1`): every addition goes through the same ledger and
 * successor, and parallel tests would only compete for them. No retry: a
 * flaky end-to-end test is a defect to fix, not to hide. Traces and
 * screenshots are kept for failures.
 *
 * Business Justification: `make e2e` must pass after every step that
 * touches the flow (CLAUDE.md 6.4).
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @module playwright.config
 * @since e2e 0.1.0
 */

import { defineConfig, devices } from "@playwright/test";

/**
 * The configuration exported to Playwright.
 *
 * Description: See the module documentation. The test timeout (2 minutes)
 * covers the slowest case, `99999+1`, with a wide margin.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @type {import("@playwright/test").PlaywrightTestConfig}
 * @since e2e 0.1.0
 */
const config = defineConfig({
  testDir: "./specs",
  timeout: 120_000,
  workers: 1,
  retries: 0,
  forbidOnly: true,
  reporter: [["list"], ["html", { outputFolder: "/results/report", open: "never" }]],
  outputDir: "/results/artifacts",
  use: {
    baseURL: process.env.AAAS_BASE_URL ?? "http://gateway:8000/",
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});

export default config;
