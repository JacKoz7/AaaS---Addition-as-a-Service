// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       repo
// Module:          commitlint.config.cjs
// Owning Team:     Platform Enablement Guild (PEG)
// Classification:  INTERNAL
// Purpose:         Commit message rules: Conventional Commits with the AaaS
//                  type list, a mandatory kebab-case scope and the mandatory
//                  `Step: P<phase>.<step>` trailer (CLAUDE.md 7.1).
// Related Docs:    CLAUDE.md (section 7.1), ADR-0005, .pre-commit-config.yaml

/**
 * Commit types allowed in this repository, in the order listed in CLAUDE.md 7.1.
 * @type {string[]}
 */
const TYPES = [
  "feat",
  "fix",
  "refactor",
  "perf",
  "test",
  "docs",
  "build",
  "ci",
  "chore",
  "contract",
  "infra",
];

/**
 * Regular expression matching one `Step: P<phase>.<step>` trailer line.
 * Sub-steps carry a letter suffix (for example `P2.13a`).
 * @type {RegExp}
 */
const STEP_TRAILER = /^Step: P\d+\.\d+[a-z]?$/gm;

/**
 * Commitlint configuration.
 *
 * The rules are written out in full instead of extending
 * `@commitlint/config-conventional`, because the pre-commit hook runs
 * commitlint from an isolated environment and `extends` is resolved from the
 * repository directory, where no node_modules exist. The first block mirrors
 * config-conventional; the second block tightens it for AaaS:
 * - type must be one of TYPES;
 * - scope is mandatory and kebab-case (service, frontend element or area);
 * - subject is imperative, must not start with a capital letter, no period;
 * - header is at most 72 characters, body and footer lines at most 100;
 * - exactly one `Step:` trailer is mandatory on every commit.
 *
 * @type {import("@commitlint/types").UserConfig}
 */
module.exports = {
  plugins: [
    {
      rules: {
        /**
         * Verifies that the commit carries exactly one `Step: P<phase>.<step>`
         * trailer line.
         * @param {{raw: string}} parsed parsed commit
         * @returns {[boolean, string]} rule outcome and message
         */
        "aaas-step-trailer": ({ raw }) => {
          const matches = raw.match(STEP_TRAILER) || [];
          if (matches.length === 1) {
            return [true, ""];
          }
          return [
            false,
            "commit must contain exactly one trailer line 'Step: P<phase>.<step>' (e.g. 'Step: P1.4')",
          ];
        },
      },
    },
  ],
  rules: {
    // --- mirrors @commitlint/config-conventional ---------------------------
    "body-leading-blank": [1, "always"],
    "body-max-line-length": [2, "always", 100],
    "footer-leading-blank": [1, "always"],
    "footer-max-line-length": [2, "always", 100],
    "header-trim": [2, "always"],
    "subject-case": [
      2,
      "never",
      ["sentence-case", "start-case", "pascal-case", "upper-case"],
    ],
    "subject-empty": [2, "never"],
    "subject-full-stop": [2, "never", "."],
    "type-case": [2, "always", "lower-case"],
    "type-empty": [2, "never"],
    // --- AaaS-specific -----------------------------------------------------
    "type-enum": [2, "always", TYPES],
    "scope-empty": [2, "never"],
    "scope-case": [2, "always", "kebab-case"],
    "header-max-length": [2, "always", 72],
    "aaas-step-trailer": [2, "always"],
  },
};
