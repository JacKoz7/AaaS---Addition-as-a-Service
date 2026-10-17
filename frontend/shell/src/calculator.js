// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       frontend-shell
// Module:          src/calculator.js
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         State of the temporary calculator page: key presses, the
//                  expression, the task and what the display shows. Pure
//                  functions, no DOM and no network.
// Related Docs:    frontend/shell/README.md, CLAUDE.md 1 and 3 (steps 1, 2
//                  and 12), ADR-0018

/**
 * State machine of the calculator.
 *
 * Description: A session starts in the phase `input`: digits and `+` are
 * appended to the expression (at most {@link MAX_EXPRESSION} characters, the
 * limit of `aaas.expression.submitted.v1`), `=` submits it and moves to
 * `waiting`, in which only `C` is accepted; the task view of
 * `GET /api/v1/tasks/{taskId}` then moves it to `done` (status `RECORDED`)
 * or `error` (status `FAILED`, or no task for {@link MISSING_TASK_LIMIT_MS}).
 * After `done` or `error`, a digit or `+` starts a new session with that
 * key, like a pocket calculator. `C` always starts a new session. Every
 * accepted key is sent to `POST /api/v1/keys` with the session and its
 * sequence number.
 *
 * TEMPORARY(P8.15): this page stands in for the single-spa shell and the
 * microfrontends of Phase 8, which split it into one element per key.
 *
 * Business Justification: The user interface of AaaS (CLAUDE.md 1): a
 * keypad, a display and nothing else.
 *
 * Thread Safety: pure functions; the state objects are never mutated.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @module calculator
 * @since shell 0.1.0
 */

/**
 * Longest expression accepted, in characters.
 *
 * Description: The `expression` pattern `^[0-9+]{1,64}$` of
 * `aaas.expression.submitted.v1`; further keys are ignored.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @type {number}
 * @since shell 0.1.0
 */
export const MAX_EXPRESSION = 64;

/**
 * How long a submitted task may stay unknown before the display shows an
 * error, in milliseconds.
 *
 * Description: The ledger knows a task a fraction of a second after `=`;
 * an expression the parser rejects (`2++3`) never becomes a task.
 * TEMPORARY(P3.6): the rejection is not reported until the dead-letter
 * service exists, so a timeout stands in for it.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @type {number}
 * @since shell 0.1.0
 */
export const MISSING_TASK_LIMIT_MS = 15000;

/**
 * Keys of the keypad, in display order.
 *
 * Description: Digits, `+`, `=` and `C` (CLAUDE.md 1).
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @type {ReadonlyArray<string>}
 * @since shell 0.1.0
 */
export const KEYS = Object.freeze(["7", "8", "9", "4", "5", "6", "1", "2", "3", "0", "+", "=", "C"]);

/**
 * @typedef {object} State
 * @property {string} sessionId Session of the key presses (UUID).
 * @property {number} seq Sequence number of the next key press, from 0.
 * @property {string} expression Keys pressed before `=`.
 * @property {"input"|"waiting"|"done"|"error"} phase Phase of the session.
 * @property {string|null} taskId Task returned for `=`.
 * @property {string|null} status Last task status, for example `COUNTING`.
 * @property {number} done Successor calls made.
 * @property {number} total Successor calls needed.
 * @property {number|null} result Sum once recorded.
 * @property {number|null} missingSince When the task was first unknown (ms).
 * @property {string} message Error message of the phase `error`.
 */

/**
 * @typedef {object} KeyPress
 * @property {string} sessionId Session.
 * @property {string} key The key.
 * @property {number} seq Its sequence number.
 * @property {string|null} idempotencyKey `Idempotency-Key` of an `=`, else null.
 */

/**
 * @typedef {object} TaskView
 * @property {string} taskId The task.
 * @property {string} status `COUNTING`, `RECORDING`, `RECORDED` or `FAILED`.
 * @property {{done: number, total: number}} progress Successor calls made and needed.
 * @property {number} [result] The sum, for `RECORDED`.
 */

/**
 * A new, empty session.
 *
 * Description: Phase `input`, empty expression, sequence 0.
 *
 * Business Justification: Every calculation runs in its own session, so
 * that the expression assembler joins exactly its key presses.
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
 * @param {string} sessionId A new UUID.
 * @returns {State} The session.
 * @since shell 0.1.0
 * @example
 * newSession("8b0f6d3e-1c2a-4b5c-9d7e-0f1a2b3c4d5e").phase; // "input"
 */
export function newSession(sessionId) {
  return Object.freeze({
    sessionId,
    seq: 0,
    expression: "",
    phase: "input",
    taskId: null,
    status: null,
    done: 0,
    total: 0,
    result: null,
    missingSince: null,
    message: "",
  });
}

/**
 * Applies a key press.
 *
 * Description: See the module documentation. A rejected key (an unknown
 * key, `=` without an expression, a key while waiting, a key beyond
 * {@link MAX_EXPRESSION}) leaves the state unchanged and sends nothing.
 *
 * Business Justification: The keypad is the only input of AaaS.
 *
 * Errors: None.
 *
 * Side Effects: None (calls `newId` for new identifiers).
 *
 * Complexity: O(1).
 *
 * Thread Safety: pure apart from `newId`.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @param {State} state The current state.
 * @param {string} key One of {@link KEYS}.
 * @param {function(): string} newId Returns a new UUID (session and idempotency key).
 * @returns {{state: State, send: KeyPress|null, cleared: boolean}} The new
 *   state, the key press to send, and whether the session was cleared.
 * @since shell 0.1.0
 * @example
 * let ids = 0;
 * const id = () => `00000000-0000-4000-8000-00000000000${ids++}`;
 * const first = press(newSession(id()), "2", id);
 * first.send; // { sessionId: "…0", key: "2", seq: 0, idempotencyKey: null }
 */
export function press(state, key, newId) {
  const unchanged = { state, send: null, cleared: false };
  if (key === "C") {
    return { state: newSession(newId()), send: null, cleared: true };
  }
  if (!KEYS.includes(key) || state.phase === "waiting") {
    return unchanged;
  }
  let current = state;
  if (state.phase === "done" || state.phase === "error") {
    if (key === "=") {
      return unchanged;
    }
    current = newSession(newId());
  }
  if (key === "=") {
    if (current.expression.length === 0) {
      return unchanged;
    }
    const send = { sessionId: current.sessionId, key, seq: current.seq, idempotencyKey: newId() };
    return {
      state: Object.freeze({ ...current, seq: current.seq + 1, phase: "waiting" }),
      send,
      cleared: current !== state,
    };
  }
  if (current.expression.length >= MAX_EXPRESSION) {
    return unchanged;
  }
  const send = { sessionId: current.sessionId, key, seq: current.seq, idempotencyKey: null };
  return {
    state: Object.freeze({ ...current, seq: current.seq + 1, expression: current.expression + key }),
    send,
    cleared: current !== state,
  };
}

/**
 * Records the task returned for `=`.
 *
 * Description: Only in the phase `waiting` of the same session; a late
 * answer for a cleared session is ignored.
 *
 * Business Justification: The display polls this task.
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
 * @param {State} state The current state.
 * @param {string} sessionId Session of the `=`.
 * @param {string} taskId The task.
 * @returns {State} The new state.
 * @since shell 0.1.0
 * @example
 * started(waiting, waiting.sessionId, "01a1…").taskId; // "01a1…"
 */
export function started(state, sessionId, taskId) {
  if (state.phase !== "waiting" || state.sessionId !== sessionId) {
    return state;
  }
  return Object.freeze({ ...state, taskId, status: "ACCEPTED" });
}

/**
 * Applies a task view of `GET /api/v1/tasks/{taskId}`.
 *
 * Description: Copies status and progress; `RECORDED` moves to `done` with
 * the result, `FAILED` to `error`. A view of another task is ignored.
 *
 * Business Justification: The display shows progress and the result
 * (CLAUDE.md 3, step 12).
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
 * @param {State} state The current state.
 * @param {TaskView} view The task view.
 * @returns {State} The new state.
 * @since shell 0.1.0
 * @example
 * observed(s, { taskId: s.taskId, status: "RECORDED", progress: { done: 3, total: 3 }, result: 5 }).result; // 5
 */
export function observed(state, view) {
  if (state.phase !== "waiting" || view.taskId !== state.taskId) {
    return state;
  }
  const next = {
    ...state,
    status: view.status,
    done: view.progress?.done ?? 0,
    total: view.progress?.total ?? 0,
    missingSince: null,
  };
  if (view.status === "RECORDED" && typeof view.result === "number") {
    return Object.freeze({ ...next, phase: "done", result: view.result });
  }
  if (view.status === "FAILED") {
    return Object.freeze({ ...next, phase: "error", message: "Error" });
  }
  return Object.freeze(next);
}

/**
 * Records that the task is unknown (404) at `nowMs`.
 *
 * Description: Remembers the first such moment; after
 * {@link MISSING_TASK_LIMIT_MS} the session moves to `error`.
 *
 * Business Justification: A rejected expression must not wait forever.
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
 * @param {State} state The current state.
 * @param {number} nowMs Current time in milliseconds.
 * @returns {State} The new state.
 * @since shell 0.1.0
 * @example
 * missing(missing(s, 0), MISSING_TASK_LIMIT_MS).phase; // "error"
 */
export function missing(state, nowMs) {
  if (state.phase !== "waiting") {
    return state;
  }
  const since = state.missingSince ?? nowMs;
  if (nowMs - since >= MISSING_TASK_LIMIT_MS) {
    return Object.freeze({ ...state, phase: "error", missingSince: since, message: "Error" });
  }
  return Object.freeze({ ...state, missingSince: since });
}

/**
 * Moves a session to `error` because the system cannot be reached.
 *
 * Description: Used when a key press could not be delivered after its
 * retries.
 *
 * Business Justification: The user sees that the calculation did not
 * start, instead of waiting.
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
 * @param {State} state The current state.
 * @param {string} sessionId Session of the failed key press.
 * @returns {State} The new state (unchanged for another session).
 * @since shell 0.1.0
 * @example
 * unavailable(s, s.sessionId).message; // "Unavailable"
 */
export function unavailable(state, sessionId) {
  if (state.sessionId !== sessionId) {
    return state;
  }
  return Object.freeze({ ...state, phase: "error", message: "Unavailable" });
}

/**
 * What the display shows.
 *
 * Description: `main` is the large line: the expression (or `0`) while
 * typing and waiting, the result when done, the message on error. `detail`
 * is the small line: the expression and `=` when done, the status and
 * progress while waiting, empty otherwise.
 *
 * Business Justification: The display of CLAUDE.md 1.
 *
 * Errors: None.
 *
 * Side Effects: None.
 *
 * Complexity: O(length of the expression).
 *
 * Thread Safety: pure.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @param {State} state The state.
 * @returns {{main: string, detail: string}} The two lines.
 * @since shell 0.1.0
 * @example
 * displayOf(newSession("x")); // { main: "0", detail: "" }
 */
export function displayOf(state) {
  switch (state.phase) {
    case "done":
      return { main: String(state.result), detail: `${state.expression} =` };
    case "error":
      return { main: state.message, detail: state.expression };
    case "waiting": {
      const progress = state.total > 0 ? ` ${state.done} / ${state.total}` : "";
      return { main: state.expression, detail: `${state.status ?? "SENDING"}${progress}` };
    }
    default:
      return { main: state.expression || "0", detail: "" };
  }
}
