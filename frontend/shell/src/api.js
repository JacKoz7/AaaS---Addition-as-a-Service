// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       frontend-shell
// Module:          src/api.js
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Calls of the public API used by the temporary page:
//                  POST /api/v1/keys and GET /api/v1/tasks/{taskId}, with a
//                  deadline and retries.
// Related Docs:    CLAUDE.md 4.1 and 6.1, services/expression-assembler/README.md,
//                  services/ledger/docs/API.md, ADR-0018

/**
 * Client of the public API.
 *
 * Description: Same-origin requests through the gateway. Each attempt has
 * a deadline of {@link TIMEOUT_MS}; a key press is retried up to
 * {@link ATTEMPTS} times with jitter when the request fails or the answer
 * is a 5xx (CLAUDE.md 6.1). A retried key press is safe: the expression
 * assembler accepts the same key at the same sequence number again, and
 * the same `Idempotency-Key` of an `=` returns the same task. The `fetch`
 * function is injected, so that the module is tested without a network.
 *
 * Business Justification: The page talks to AaaS only through the public
 * API (CLAUDE.md 4.1).
 *
 * Thread Safety: browser main thread; no shared state.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @module api
 * @since shell 0.1.0
 */

/**
 * Deadline of one request, in milliseconds (CLAUDE.md 6.1).
 *
 * Description: Covers connection and answer.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @type {number}
 * @since shell 0.1.0
 */
export const TIMEOUT_MS = 2000;

/**
 * Attempts per key press (CLAUDE.md 6.1).
 *
 * Description: The first attempt and two retries.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @type {number}
 * @since shell 0.1.0
 */
export const ATTEMPTS = 3;

/**
 * Waits `ms` milliseconds.
 *
 * Description: The default pause between retries.
 *
 * Business Justification: Retries are spread out.
 *
 * Errors: None.
 *
 * Side Effects: a timer.
 *
 * Complexity: O(1).
 *
 * Thread Safety: browser main thread.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @param {number} ms Milliseconds.
 * @returns {Promise<void>} Resolves after the delay.
 * @since shell 0.1.0
 */
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Sends one key press; retries transient failures.
 *
 * Description: `POST /api/v1/keys` with `{sessionId, key, seq}` and, for
 * `=`, the `Idempotency-Key` header. `204` is a recorded key, `202` an
 * accepted `=` with its `taskId`. A `4xx` is final; a network error, a
 * timeout or a `5xx` is retried after a random pause of up to 200 ms times
 * the attempt number.
 *
 * Business Justification: Every key press of the keypad reaches the
 * expression assembler (CLAUDE.md 3, steps 1 and 2).
 *
 * Errors: None (failures are returned as `ok: false`).
 *
 * Side Effects: 1..{@link ATTEMPTS} HTTP requests.
 *
 * Complexity: O(1).
 *
 * Thread Safety: browser main thread.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @param {function(string, object=): Promise<Response>} fetchFn The fetch function.
 * @param {module:calculator~KeyPress} keyPress The key press.
 * @param {function(number): Promise<void>} [pause] Pause between attempts.
 * @returns {Promise<{ok: boolean, taskId: string|null, status: number}>} Whether it was
 *   accepted, the task of an `=`, and the last HTTP status (0 without an answer).
 * @since shell 0.1.0
 * @example
 * const r = await sendKey(fetch, { sessionId, key: "=", seq: 3, idempotencyKey });
 * r.taskId; // "01a14aa9-5613-7d39-a926-f4181f33b699"
 */
export async function sendKey(fetchFn, keyPress, pause = sleep) {
  const headers = { "Content-Type": "application/json" };
  if (keyPress.idempotencyKey) {
    headers["Idempotency-Key"] = keyPress.idempotencyKey;
  }
  const body = JSON.stringify({ sessionId: keyPress.sessionId, key: keyPress.key, seq: keyPress.seq });
  let status = 0;
  for (let attempt = 1; attempt <= ATTEMPTS; attempt++) {
    try {
      const resp = await fetchFn("/api/v1/keys", {
        method: "POST",
        headers,
        body,
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
      status = resp.status;
      if (resp.status === 202) {
        const answer = await resp.json();
        return { ok: true, taskId: answer.taskId ?? null, status };
      }
      if (resp.status >= 200 && resp.status < 300) {
        return { ok: true, taskId: null, status };
      }
      if (resp.status < 500) {
        return { ok: false, taskId: null, status };
      }
    } catch {
      status = 0;
    }
    if (attempt < ATTEMPTS) {
      await pause(Math.random() * 200 * attempt);
    }
  }
  return { ok: false, taskId: null, status };
}

/**
 * Reads the status of a task.
 *
 * Description: `GET /api/v1/tasks/{taskId}`. One attempt: the caller polls
 * every second anyway. `200` gives the view, `404` means not known yet,
 * anything else (including a timeout) is reported as unavailable.
 *
 * Business Justification: The display shows progress and the result
 * (CLAUDE.md 3, step 12).
 *
 * Errors: None (failures are returned as `kind: "unavailable"`).
 *
 * Side Effects: one HTTP request.
 *
 * Complexity: O(size of the answer).
 *
 * Thread Safety: browser main thread.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @param {function(string, object=): Promise<Response>} fetchFn The fetch function.
 * @param {string} taskId The task.
 * @returns {Promise<{kind: "found"|"missing"|"unavailable", view: object|null}>} The outcome.
 * @since shell 0.1.0
 * @example
 * const r = await fetchTask(fetch, taskId);
 * if (r.kind === "found") console.log(r.view.status);
 */
export async function fetchTask(fetchFn, taskId) {
  try {
    const resp = await fetchFn(`/api/v1/tasks/${encodeURIComponent(taskId)}`, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (resp.status === 200) {
      return { kind: "found", view: await resp.json() };
    }
    if (resp.status === 404) {
      return { kind: "missing", view: null };
    }
  } catch {
    // A timeout or a network error: try again at the next poll.
  }
  return { kind: "unavailable", view: null };
}
