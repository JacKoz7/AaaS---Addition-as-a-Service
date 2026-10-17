// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       frontend-shell
// Module:          tests/calculator.test.js
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Unit tests of the calculator state machine.
// Related Docs:    frontend/shell/src/calculator.js, ADR-0018

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  KEYS,
  MAX_EXPRESSION,
  MISSING_TASK_LIMIT_MS,
  displayOf,
  missing,
  newSession,
  observed,
  press,
  started,
  unavailable,
} from "../src/calculator.js";

/**
 * A generator of predictable UUIDs.
 *
 * Description: `00000000-0000-4000-8000-0000000000NN`, counting from 0.
 *
 * Business Justification: Deterministic tests.
 *
 * Errors: None.
 *
 * Side Effects: None outside the returned closure.
 *
 * Complexity: O(1) per identifier.
 *
 * Thread Safety: single-threaded tests.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @returns {function(): string} The generator.
 * @since shell 0.1.0
 */
function ids() {
  let n = 0;
  return () => `00000000-0000-4000-8000-${String(n++).padStart(12, "0")}`;
}

/**
 * Presses `keys` in order.
 *
 * Description: Collects the key presses to send.
 *
 * Business Justification: Shorter tests.
 *
 * Errors: None.
 *
 * Side Effects: None.
 *
 * Complexity: O(number of keys).
 *
 * Thread Safety: single-threaded tests.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @param {import("../src/calculator.js").State} state The start state.
 * @param {string} keys The keys, one character each.
 * @param {function(): string} newId UUID generator.
 * @returns {{state: import("../src/calculator.js").State, sent: Array<object>}} The final
 *   state and the key presses.
 * @since shell 0.1.0
 */
function pressAll(state, keys, newId) {
  const sent = [];
  for (const key of keys) {
    const outcome = press(state, key, newId);
    state = outcome.state;
    if (outcome.send) sent.push(outcome.send);
  }
  return { state, sent };
}

test("the keypad has the keys of CLAUDE.md 1 and nothing else", () => {
  assert.deepEqual([...KEYS].sort(), ["+", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "=", "C"]);
});

test("2+3= sends four keys in order, the = with an idempotency key", () => {
  const newId = ids();
  const { state, sent } = pressAll(newSession(newId()), "2+3=", newId);
  assert.deepEqual(
    sent.map((s) => [s.key, s.seq]),
    [
      ["2", 0],
      ["+", 1],
      ["3", 2],
      ["=", 3],
    ],
  );
  assert.ok(sent.every((s) => s.sessionId === state.sessionId));
  assert.equal(sent[3].idempotencyKey, "00000000-0000-4000-8000-000000000001");
  assert.equal(sent[0].idempotencyKey, null);
  assert.equal(state.phase, "waiting");
  assert.deepEqual(displayOf(state), { main: "2+3", detail: "SENDING" });
});

test("= without an expression and keys while waiting are ignored", () => {
  const newId = ids();
  const empty = newSession(newId());
  assert.equal(press(empty, "=", newId).send, null);
  const { state } = pressAll(empty, "1=", newId);
  const again = press(state, "5", newId);
  assert.equal(again.send, null);
  assert.equal(again.state, state);
  assert.equal(press(state, "x", newId).send, null);
});

test("the expression stops at the contract limit", () => {
  const newId = ids();
  const { state, sent } = pressAll(newSession(newId()), "9".repeat(MAX_EXPRESSION + 5), newId);
  assert.equal(state.expression.length, MAX_EXPRESSION);
  assert.equal(sent.length, MAX_EXPRESSION);
});

test("C starts a new session in every phase", () => {
  const newId = ids();
  const { state } = pressAll(newSession(newId()), "12=", newId);
  const cleared = press(state, "C", newId);
  assert.equal(cleared.cleared, true);
  assert.equal(cleared.send, null);
  assert.notEqual(cleared.state.sessionId, state.sessionId);
  assert.deepEqual(displayOf(cleared.state), { main: "0", detail: "" });
});

test("the task view drives progress and the result", () => {
  const newId = ids();
  let { state } = pressAll(newSession(newId()), "2+3=", newId);
  state = started(state, state.sessionId, "t1");
  assert.equal(state.status, "ACCEPTED");
  state = observed(state, { taskId: "t1", status: "COUNTING", progress: { done: 1, total: 3 } });
  assert.deepEqual(displayOf(state), { main: "2+3", detail: "COUNTING 1 / 3" });
  assert.equal(observed(state, { taskId: "other", status: "RECORDED", progress: {}, result: 9 }), state);
  state = observed(state, { taskId: "t1", status: "RECORDED", progress: { done: 3, total: 3 }, result: 5 });
  assert.equal(state.phase, "done");
  assert.deepEqual(displayOf(state), { main: "5", detail: "2+3 =" });
});

test("after a result a digit starts a new calculation", () => {
  const newId = ids();
  let { state } = pressAll(newSession(newId()), "2+3=", newId);
  state = observed(started(state, state.sessionId, "t1"), {
    taskId: "t1",
    status: "RECORDED",
    progress: { done: 3, total: 3 },
    result: 5,
  });
  const next = press(state, "7", newId);
  assert.equal(next.cleared, true);
  assert.equal(next.send.seq, 0);
  assert.notEqual(next.send.sessionId, state.sessionId);
  assert.equal(next.state.expression, "7");
  assert.equal(press(state, "=", newId).send, null);
});

test("a task unknown for too long and a FAILED task are errors", () => {
  const newId = ids();
  let { state } = pressAll(newSession(newId()), "2++3=", newId);
  state = started(state, state.sessionId, "t1");
  state = missing(state, 1000);
  assert.equal(state.phase, "waiting");
  state = missing(state, 1000 + MISSING_TASK_LIMIT_MS - 1);
  assert.equal(state.phase, "waiting");
  state = missing(state, 1000 + MISSING_TASK_LIMIT_MS);
  assert.deepEqual(displayOf(state), { main: "Error", detail: "2++3" });

  let other = pressAll(newSession(newId()), "1+1=", newId).state;
  other = observed(started(other, other.sessionId, "t2"), { taskId: "t2", status: "FAILED", progress: {} });
  assert.equal(other.phase, "error");
});

test("a found task resets the missing clock; late answers of an old session are ignored", () => {
  const newId = ids();
  let { state } = pressAll(newSession(newId()), "4+4=", newId);
  state = started(state, state.sessionId, "t1");
  state = missing(state, 0);
  state = observed(state, { taskId: "t1", status: "COUNTING", progress: { done: 0, total: 4 } });
  assert.equal(state.missingSince, null);
  assert.equal(started(state, "another-session", "t9"), state);
  assert.equal(unavailable(state, "another-session"), state);
  assert.equal(unavailable(state, state.sessionId).message, "Unavailable");
});
