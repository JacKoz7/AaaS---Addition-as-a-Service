// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       frontend-shell
// Module:          tests/api.test.js
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Unit tests of the public API client with a fake fetch.
// Related Docs:    frontend/shell/src/api.js, ADR-0018

import { test } from "node:test";
import assert from "node:assert/strict";
import { ATTEMPTS, fetchTask, sendKey } from "../src/api.js";

/**
 * A fake `fetch` answering from a list, recording the requests.
 *
 * Description: Each entry is a status and an optional JSON body, or an
 * `Error` to throw; the last entry repeats.
 *
 * Business Justification: Tests without a network.
 *
 * Errors: throws the `Error` entries.
 *
 * Side Effects: records every call.
 *
 * Complexity: O(1) per call.
 *
 * Thread Safety: single-threaded tests.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @param {Array<{status: number, body?: object}|Error>} answers The answers.
 * @returns {{fetchFn: typeof fetch, calls: Array<{url: string, init: object}>}} The fake and its log.
 * @since shell 0.1.0
 */
function fakeFetch(answers) {
  const calls = [];
  let i = 0;
  const fetchFn = async (url, init = {}) => {
    calls.push({ url, init });
    const answer = answers[Math.min(i++, answers.length - 1)];
    if (answer instanceof Error) throw answer;
    return { status: answer.status, json: async () => answer.body };
  };
  return { fetchFn, calls };
}

/**
 * A pause that does not wait.
 *
 * Description: Replaces the retry delay.
 *
 * Business Justification: Fast tests.
 *
 * Errors: None.
 *
 * Side Effects: None.
 *
 * Complexity: O(1).
 *
 * Thread Safety: single-threaded tests.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @returns {Promise<void>} Resolved at once.
 * @since shell 0.1.0
 */
async function noPause() {}

/**
 * A digit key press.
 *
 * Description: Session `s`, key `2`, sequence 0.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @type {import("../src/calculator.js").KeyPress}
 * @since shell 0.1.0
 */
const digit = { sessionId: "s", key: "2", seq: 0, idempotencyKey: null };

test("a key press is posted with its session and sequence", async () => {
  const { fetchFn, calls } = fakeFetch([{ status: 204 }]);
  assert.deepEqual(await sendKey(fetchFn, digit, noPause), { ok: true, taskId: null, status: 204 });
  assert.equal(calls[0].url, "/api/v1/keys");
  assert.equal(calls[0].init.method, "POST");
  assert.deepEqual(JSON.parse(calls[0].init.body), { sessionId: "s", key: "2", seq: 0 });
  assert.equal(calls[0].init.headers["Idempotency-Key"], undefined);
  assert.ok(calls[0].init.signal);
});

test("= carries the Idempotency-Key and returns the task", async () => {
  const { fetchFn, calls } = fakeFetch([{ status: 202, body: { taskId: "t1" } }]);
  const equals = { sessionId: "s", key: "=", seq: 3, idempotencyKey: "k" };
  assert.deepEqual(await sendKey(fetchFn, equals, noPause), { ok: true, taskId: "t1", status: 202 });
  assert.equal(calls[0].init.headers["Idempotency-Key"], "k");
});

test("network errors and 5xx are retried, 4xx are not", async () => {
  const retried = fakeFetch([new Error("down"), { status: 502 }, { status: 204 }]);
  assert.equal((await sendKey(retried.fetchFn, digit, noPause)).ok, true);
  assert.equal(retried.calls.length, 3);

  const exhausted = fakeFetch([{ status: 503 }]);
  assert.deepEqual(await sendKey(exhausted.fetchFn, digit, noPause), { ok: false, taskId: null, status: 503 });
  assert.equal(exhausted.calls.length, ATTEMPTS);

  const refused = fakeFetch([{ status: 409 }]);
  assert.equal((await sendKey(refused.fetchFn, digit, noPause)).ok, false);
  assert.equal(refused.calls.length, 1);
});

test("task status: found, missing, unavailable", async () => {
  const view = { taskId: "t1", status: "RECORDED", progress: { done: 3, total: 3 }, result: 5 };
  const found = fakeFetch([{ status: 200, body: view }]);
  assert.deepEqual(await fetchTask(found.fetchFn, "t1"), { kind: "found", view });
  assert.equal(found.calls[0].url, "/api/v1/tasks/t1");
  assert.equal((await fetchTask(fakeFetch([{ status: 404 }]).fetchFn, "t1")).kind, "missing");
  assert.equal((await fetchTask(fakeFetch([{ status: 502 }]).fetchFn, "t1")).kind, "unavailable");
  assert.equal((await fetchTask(fakeFetch([new Error("x")]).fetchFn, "t1")).kind, "unavailable");
});
