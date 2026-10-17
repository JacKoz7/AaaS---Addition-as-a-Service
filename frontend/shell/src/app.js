// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       frontend-shell
// Module:          src/app.js
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         The temporary calculator page: connects the keypad, the
//                  display, the public API and the browser event bus.
// Related Docs:    frontend/shell/README.md, CLAUDE.md 2 (microfrontends) and
//                  3 (step 12), ADR-0018

/**
 * The calculator page.
 *
 * Description: {@link createApp} wires the parts the way the
 * microfrontends of Phase 8 will talk, through `window` events with the
 * `aaas:` prefix (CLAUDE.md 2):
 *
 * - a keypad button publishes `aaas:key-pressed {key}`;
 * - the page applies it ({@link module:calculator.press}), sends accepted
 *   keys to `POST /api/v1/keys` one after another, in order, and publishes
 *   `aaas:clear` for `C`;
 * - the answer to `=` publishes `aaas:task-started {taskId}` and starts
 *   polling `GET /api/v1/tasks/{taskId}` every {@link POLL_MS};
 * - a recorded task publishes `aaas:task-finished {taskId, result}`.
 *
 * TEMPORARY(P8.15): one page instead of the single-spa shell (P8.1), the
 * display (P8.2) and the key microfrontends (P8.3–P8.15).
 *
 * Business Justification: The first addition clicked by a user, "2+3="
 * (step P1.8; milestone M1 with P1.9).
 *
 * Thread Safety: browser main thread.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @module app
 * @since shell 0.1.0
 */

import { displayOf, missing, newSession, observed, press, started, unavailable } from "./calculator.js";
import { fetchTask, sendKey } from "./api.js";

/**
 * Interval between two task status requests, in milliseconds.
 *
 * Description: Once per second (CLAUDE.md 3, step 12).
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @type {number}
 * @since shell 0.1.0
 */
export const POLL_MS = 1000;

/**
 * @typedef {object} AppDeps
 * @property {EventTarget} bus The event bus (`window`).
 * @property {{textContent: string}} main Large display line.
 * @property {{textContent: string}} detail Small display line.
 * @property {function(string, object=): Promise<Response>} fetchFn The fetch function.
 * @property {function(): string} newId Returns a new UUID.
 * @property {function(): number} now Current time in milliseconds.
 * @property {function(function(): void, number): unknown} setTimer Schedules a callback.
 */

/**
 * Starts the page logic.
 *
 * Description: See the module documentation. Key presses of a session are
 * sent strictly in order; once one of them fails after its retries, the
 * session shows `Unavailable` and its remaining keys are not sent. A late
 * answer or poll for a cleared session is ignored.
 *
 * Business Justification: See the module documentation.
 *
 * Errors: None (failures are shown on the display).
 *
 * Side Effects: listens to `aaas:key-pressed`; publishes `aaas:clear`,
 * `aaas:task-started` and `aaas:task-finished`; HTTP requests; writes the
 * display.
 *
 * Complexity: O(1) per key press and per poll.
 *
 * Thread Safety: browser main thread.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @param {AppDeps} deps The dependencies.
 * @returns {{state: function(): module:calculator~State, idle: function(): Promise<void>}}
 *   Accessors for tests: the current state and a promise of the sent keys.
 * @since shell 0.1.0
 * @example
 * createApp({ bus: window, main, detail, fetchFn: fetch.bind(window),
 *   newId: randomUuid, now: Date.now, setTimer: setTimeout });
 */
export function createApp(deps) {
  let state = newSession(deps.newId());
  let queue = Promise.resolve();
  const failed = new Set();

  /**
   * Writes the display from the state.
   *
   * Description: Both lines.
   *
   * Business Justification: The display shows the state.
   *
   * Errors: None.
   *
   * Side Effects: writes two elements.
   *
   * Complexity: O(length of the expression).
   *
   * Thread Safety: browser main thread.
   *
   * Owner: Customer Experience Tribe (CXT).
   *
   * @returns {void}
   * @since shell 0.1.0
   */
  function render() {
    const view = displayOf(state);
    deps.main.textContent = view.main;
    deps.detail.textContent = view.detail;
  }

  /**
   * Polls the task until it is done, failed, or no longer current.
   *
   * Description: One request, then the next one {@link POLL_MS} later.
   *
   * Business Justification: CLAUDE.md 3, step 12.
   *
   * Errors: None.
   *
   * Side Effects: one HTTP request per call; may publish
   * `aaas:task-finished`.
   *
   * Complexity: O(1).
   *
   * Thread Safety: browser main thread.
   *
   * Owner: Customer Experience Tribe (CXT).
   *
   * @param {string} taskId The task.
   * @returns {Promise<void>} Resolves after this poll.
   * @since shell 0.1.0
   */
  async function poll(taskId) {
    if (state.taskId !== taskId || state.phase !== "waiting") {
      return;
    }
    const answer = await fetchTask(deps.fetchFn, taskId);
    if (state.taskId !== taskId) {
      return;
    }
    if (answer.kind === "found") {
      state = observed(state, answer.view);
    } else if (answer.kind === "missing") {
      state = missing(state, deps.now());
    }
    render();
    if (state.phase === "done") {
      deps.bus.dispatchEvent(new CustomEvent("aaas:task-finished", { detail: { taskId, result: state.result } }));
    } else if (state.phase === "waiting") {
      deps.setTimer(() => void poll(taskId), POLL_MS);
    }
  }

  /**
   * Sends a key press after the previous ones.
   *
   * Description: Skips keys of a session whose earlier key failed.
   *
   * Business Justification: The expression assembler joins keys by their
   * sequence; sending in order keeps the expression intact.
   *
   * Errors: None.
   *
   * Side Effects: HTTP requests; may publish `aaas:task-started`.
   *
   * Complexity: O(1).
   *
   * Thread Safety: browser main thread.
   *
   * Owner: Customer Experience Tribe (CXT).
   *
   * @param {module:calculator~KeyPress} keyPress The key press.
   * @returns {void}
   * @since shell 0.1.0
   */
  function enqueue(keyPress) {
    queue = queue.then(async () => {
      if (failed.has(keyPress.sessionId)) {
        return;
      }
      const answer = await sendKey(deps.fetchFn, keyPress);
      if (!answer.ok) {
        failed.add(keyPress.sessionId);
        state = unavailable(state, keyPress.sessionId);
        render();
        return;
      }
      if (keyPress.key === "=" && answer.taskId) {
        const before = state;
        state = started(state, keyPress.sessionId, answer.taskId);
        if (state !== before) {
          deps.bus.dispatchEvent(new CustomEvent("aaas:task-started", { detail: { taskId: answer.taskId } }));
          render();
          void poll(answer.taskId);
        }
      }
    });
  }

  deps.bus.addEventListener("aaas:key-pressed", (event) => {
    const outcome = press(state, event.detail?.key, deps.newId);
    state = outcome.state;
    if (outcome.cleared && event.detail?.key === "C") {
      deps.bus.dispatchEvent(new CustomEvent("aaas:clear"));
    }
    render();
    if (outcome.send) {
      enqueue(outcome.send);
    }
  });
  render();
  return { state: () => state, idle: () => queue };
}
