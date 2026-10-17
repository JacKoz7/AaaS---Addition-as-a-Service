// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       e2e
// Module:          tests/e2e/specs/addition.spec.js
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         End-to-end cases of the addition: clicked in the browser
//                  through the gateway, and the idempotency of `=` through
//                  the public API.
// Related Docs:    tests/e2e/README.md, CLAUDE.md 6.4 and 9.2 (M1), ADR-0019

/**
 * Addition end to end.
 *
 * Description: Every case opens the calculator on the gateway, presses the
 * keys and waits for the display, so it exercises the whole flow:
 * frontend → gateway → expression-assembler → Redpanda → parser → ledger →
 * successor → ledger → gateway → frontend. The cases of `CLAUDE.md` 6.4 that
 * need later steps (commutativity with the commutator of P2.15, out-of-range
 * operands with the validator of P2.14) are added by P2.18.
 *
 * Business Justification: Milestone M1: `2+3=5` goes through the gateway
 * and the frontend shows the result (`CLAUDE.md` 9.2).
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @module addition.spec
 * @since e2e 0.1.0
 */

import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { add, expectDisplay, pressKeys } from "../lib/calculator.js";

/**
 * Polls `GET /api/v1/tasks/{taskId}` until the task is `RECORDED` or
 * `FAILED`.
 *
 * Description: One request every 500 ms for at most 60 s; a 404 (not known
 * yet) is retried.
 *
 * Business Justification: The API-level case checks the recorded result
 * without the page.
 *
 * Errors: an assertion error if the task does not finish in time.
 *
 * Side Effects: HTTP requests.
 *
 * Complexity: O(waiting time / 500 ms).
 *
 * Thread Safety: one request context per test.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @param {import("@playwright/test").APIRequestContext} request The request context.
 * @param {string} taskId The task.
 * @returns {Promise<object>} The final task view.
 * @since e2e 0.1.0
 */
async function finishedTask(request, taskId) {
  let view = null;
  await expect
    .poll(
      async () => {
        const resp = await request.get(`api/v1/tasks/${taskId}`);
        view = resp.status() === 200 ? await resp.json() : null;
        return view?.status ?? `HTTP ${resp.status()}`;
      },
      { timeout: 60_000, intervals: [500] },
    )
    .toMatch(/^(RECORDED|FAILED)$/);
  return view;
}

test.beforeEach(async ({ page }) => {
  await page.goto("/");
  await expectDisplay(page, "0", 10_000);
});

test("2 + 3 = 5 through the gateway (M1)", async ({ page }) => {
  await add(page, 2, 3, 5);
});

test("0 + 0 = 0, 9 + 1 = 10 and 99999 + 1 = 100000 in one session of the page", async ({ page }) => {
  await add(page, 0, 0, 0);
  await add(page, 9, 1, 10);
  await add(page, 99999, 1, 100000);
});

test("C clears the expression", async ({ page }) => {
  await pressKeys(page, "12+");
  await expectDisplay(page, "12+");
  await pressKeys(page, "C");
  await expectDisplay(page, "0");
  await add(page, 4, 4, 8);
});

test("the same Idempotency-Key of = returns the same task, recorded once", async ({ request }) => {
  const sessionId = randomUUID();
  const idempotencyKey = randomUUID();
  let seq = 0;
  for (const key of ["4", "+", "2"]) {
    const resp = await request.post("api/v1/keys", { data: { sessionId, key, seq: seq++ } });
    expect(resp.status()).toBe(204);
  }
  const equals = { data: { sessionId, key: "=", seq }, headers: { "Idempotency-Key": idempotencyKey } };
  const first = await request.post("api/v1/keys", equals);
  const second = await request.post("api/v1/keys", equals);
  expect(first.status()).toBe(202);
  expect(second.status()).toBe(202);
  const { taskId } = await first.json();
  expect((await second.json()).taskId).toBe(taskId);
  const view = await finishedTask(request, taskId);
  expect(view).toMatchObject({ taskId, status: "RECORDED", a: 4, b: 2, result: 6 });
});
