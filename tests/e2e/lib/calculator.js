// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       e2e
// Module:          tests/e2e/lib/calculator.js
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Page object of the calculator: presses keys by their
//                  accessible names and reads the display.
// Related Docs:    tests/e2e/README.md, frontend/shell/README.md, ADR-0019

/**
 * Calculator page object.
 *
 * Description: Keys are found by role and accessible name (`0`–`9`,
 * `Plus`, `Equals`, `Clear`), the display by `#display-main` and
 * `#display-detail`, as the user and assistive technologies see them. The
 * page object hides these details so that the specs survive the switch to
 * the microfrontends of Phase 8 as long as the names stay.
 *
 * Business Justification: The end-to-end tests drive the product exactly as
 * a user does.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @module calculator
 * @since e2e 0.1.0
 */

import { expect } from "@playwright/test";

/**
 * Accessible names of the non-digit keys.
 *
 * Description: Digits are named by themselves.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @type {Readonly<Record<string, string>>}
 * @since e2e 0.1.0
 */
export const KEY_NAMES = Object.freeze({ "+": "Plus", "=": "Equals", C: "Clear" });

/**
 * Presses keys one by one.
 *
 * Description: Each character of `keys` is one key; `+`, `=` and `C` are
 * mapped to their accessible names.
 *
 * Business Justification: Every test starts with key presses.
 *
 * Errors: a Playwright timeout if a key button does not exist.
 *
 * Side Effects: clicks in the page (each click sends a key press).
 *
 * Complexity: O(number of keys).
 *
 * Thread Safety: one page per test.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @param {import("@playwright/test").Page} page The page.
 * @param {string} keys The keys, for example `2+3=`.
 * @returns {Promise<void>} Resolves after the last click.
 * @since e2e 0.1.0
 * @example
 * await pressKeys(page, "2+3=");
 */
export async function pressKeys(page, keys) {
  for (const key of keys) {
    await page.getByRole("button", { name: KEY_NAMES[key] ?? key, exact: true }).click();
  }
}

/**
 * Waits until the display shows `expected` on its main line.
 *
 * Description: Polls the display (Playwright's web-first assertion) for at
 * most `timeoutMs`.
 *
 * Business Justification: The result appears when the ledger has recorded
 * it, a time that depends on the operands.
 *
 * Errors: an assertion error with the last displayed text after the
 * timeout.
 *
 * Side Effects: None.
 *
 * Complexity: O(timeoutMs / polling interval).
 *
 * Thread Safety: one page per test.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @param {import("@playwright/test").Page} page The page.
 * @param {string} expected The expected main line, for example `5`.
 * @param {number} [timeoutMs] Longest wait (default 60 s).
 * @returns {Promise<void>} Resolves when shown.
 * @since e2e 0.1.0
 * @example
 * await expectDisplay(page, "5");
 */
export async function expectDisplay(page, expected, timeoutMs = 60_000) {
  await expect(page.locator("#display-main")).toHaveText(expected, { timeout: timeoutMs });
}

/**
 * Presses `a+b=` and checks that the display shows `sum` and `a+b =`.
 *
 * Description: Starts from the current page state; after a result, the
 * next digit starts a new calculation, so cases can follow each other on
 * one page.
 *
 * Business Justification: The core scenario of AaaS.
 *
 * Errors: an assertion error if the result is not shown in time.
 *
 * Side Effects: key presses; one addition in the system.
 *
 * Complexity: O(b) on the server (b successor calls).
 *
 * Thread Safety: one page per test.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @param {import("@playwright/test").Page} page The page.
 * @param {number} a First operand.
 * @param {number} b Second operand.
 * @param {number} sum The expected result.
 * @returns {Promise<void>} Resolves when the result is shown.
 * @since e2e 0.1.0
 * @example
 * await add(page, 2, 3, 5);
 */
export async function add(page, a, b, sum) {
  await pressKeys(page, `${a}+${b}=`);
  await expectDisplay(page, String(sum));
  await expect(page.locator("#display-detail")).toHaveText(`${a}+${b} =`);
}
