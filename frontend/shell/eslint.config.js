// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       frontend-shell
// Module:          eslint.config.js
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         ESLint configuration: the recommended rules and the
//                  documentation rules of CLAUDE.md 6.5.3/6.5.4 enforced with
//                  eslint-plugin-jsdoc.
// Related Docs:    CLAUDE.md 6.3 and 6.5.4, ADR-0009, ADR-0018

/**
 * ESLint flat configuration.
 *
 * Description: `eslint .` applies the recommended JavaScript rules and the
 * documentation rules; with `AAAS_DOCS_ONLY=1` (the `doc-coverage` stage)
 * only the documentation rules run. Every function declaration and
 * top-level constant needs a JSDoc block with a description, the fields
 * `Description:`, `Errors:` (functions), `Side Effects:` (functions),
 * `Complexity:` (functions), `Thread Safety:` (functions) and `Owner:`, a
 * `@since` tag, every parameter, the return value and, for exported
 * functions, an `@example`.
 *
 * Business Justification: `make doc-coverage` must show 100% (CLAUDE.md
 * 6.5.4: eslint-plugin-jsdoc, require-jsdoc everywhere).
 *
 * Thread Safety: configuration data.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @module eslint.config
 * @since shell 0.1.0
 */

import js from "@eslint/js";
import jsdoc from "eslint-plugin-jsdoc";
import globals from "globals";

/**
 * AST selectors of the definitions that need documentation.
 *
 * Description: Function declarations at any level, declarations at the
 * top level of a module and every export (an exported function or
 * constant carries its block on the export).
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @type {string[]}
 * @since shell 0.1.0
 */
const DEFINITIONS = ["FunctionDeclaration", "Program > VariableDeclaration", "ExportNamedDeclaration"];

/**
 * Node types whose JSDoc blocks are checked for the fields.
 *
 * Description: Plain node types: the field checks of
 * `jsdoc/no-restricted-syntax` do not match combinator selectors, and only
 * nodes that have a JSDoc block are checked, so inner undocumented
 * constants are not affected.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @type {string[]}
 * @since shell 0.1.0
 */
const DOCUMENTED = ["FunctionDeclaration", "VariableDeclaration", "ExportNamedDeclaration"];

/**
 * Text fields every function documents (CLAUDE.md 6.5.3).
 *
 * Description: `Summary` is the first sentence, `Parameters`, `Returns`,
 * `Since`, `Example` and `See Also` are JSDoc tags.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @type {string[]}
 * @since shell 0.1.0
 */
const FUNCTION_FIELDS = [
  "Description",
  "Business Justification",
  "Errors",
  "Side Effects",
  "Complexity",
  "Thread Safety",
  "Owner",
];

/**
 * Builds a `jsdoc/no-restricted-syntax` rule entry that reports a JSDoc
 * block of `context` whose description lacks `text`.
 *
 * Description: esquery matches the block description against a regular
 * expression; the entry selects the blocks that do not match.
 *
 * Business Justification: The corporate fields of CLAUDE.md 6.5.3 are
 * checked, not only the presence of a comment.
 *
 * Errors: None.
 *
 * Side Effects: None.
 *
 * Complexity: O(1).
 *
 * Thread Safety: pure.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @param {string} context The AST selector.
 * @param {string} text The field name.
 * @returns {{comment: string, context: string, message: string}} The entry.
 * @since shell 0.1.0
 */
function requireField(context, text) {
  return {
    comment: `JsdocBlock:not([description=/${text}:/])`,
    context,
    message: `JSDoc must contain "${text}:" (CLAUDE.md 6.5.3)`,
  };
}

/**
 * The documentation rules.
 *
 * Description: Shared by the full lint and the `doc-coverage` stage.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @type {import("eslint").Linter.RulesRecord}
 * @since shell 0.1.0
 */
const DOC_RULES = {
  "jsdoc/require-jsdoc": ["error", { publicOnly: false, require: {}, contexts: DEFINITIONS }],
  "jsdoc/require-description": ["error", { contexts: DEFINITIONS }],
  "jsdoc/require-param": "error",
  "jsdoc/require-param-description": "error",
  "jsdoc/require-param-type": "error",
  "jsdoc/require-returns": ["error", { forceRequireReturn: true, contexts: ["FunctionDeclaration"] }],
  "jsdoc/require-returns-description": "error",
  "jsdoc/require-example": ["error", { contexts: ["ExportNamedDeclaration > FunctionDeclaration"] }],
  "jsdoc/check-param-names": "error",
  "jsdoc/check-tag-names": "error",
  "jsdoc/no-restricted-syntax": [
    "error",
    {
      contexts: [
        ...DOCUMENTED.map((context) => ({
          comment: "JsdocBlock:not(:has(JsdocTag[tag=since]))",
          context,
          message: "JSDoc must have a @since tag (CLAUDE.md 6.5.3)",
        })),
        ...DOCUMENTED.flatMap((context) => ["Description", "Owner"].map((f) => requireField(context, f))),
        ...FUNCTION_FIELDS.map((f) => requireField("FunctionDeclaration", f)),
      ],
    },
  ],
};

/**
 * The flat configuration exported to ESLint.
 *
 * Description: Browser and Node globals, ES modules, the generated
 * directories ignored.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @type {import("eslint").Linter.Config[]}
 * @since shell 0.1.0
 */
const config = [
  { ignores: ["node_modules/", "build/"] },
  {
    files: ["**/*.js"],
    languageOptions: {
      ecmaVersion: 2024,
      sourceType: "module",
      globals: { ...globals.browser, ...globals.node },
    },
    plugins: { jsdoc },
    rules: process.env.AAAS_DOCS_ONLY ? DOC_RULES : { ...js.configs.recommended.rules, ...DOC_RULES },
  },
];

export default config;
