// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       frontend-shell
// Module:          tests/app.test.js
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Tests of the page logic with a fake event bus, fake
//                  display elements, a fake fetch and manual timers.
// Related Docs:    frontend/shell/src/app.js, CLAUDE.md 2 (event bus), ADR-0018

import { test } from "node:test";
import assert from "node:assert/strict";
import { POLL_MS, createApp } from "../src/app.js";

/**
 * A fake public API: records key presses and answers task polls in order.
 *
 * Description: `POST /api/v1/keys` answers 204, or 202 with `taskId` for
 * `=`; `GET /api/v1/tasks/...` answers the next entry of `polls` (the last
 * one repeats).
 *
 * Business Justification: The page is tested without a gateway.
 *
 * Errors: None.
 *
 * Side Effects: records requests.
 *
 * Complexity: O(1) per request.
 *
 * Thread Safety: single-threaded tests.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @param {Array<{status: number, body?: object}>} polls Answers of the task polls.
 * @param {number} [keyStatus] Status of key presses (default 204/202).
 * @returns {{fetchFn: typeof fetch, keys: Array<object>, pollCount: function(): number}} The fake.
 * @since shell 0.1.0
 */
function fakeApi(polls, keyStatus) {
  const keys = [];
  let pollIndex = 0;
  const fetchFn = async (url, init = {}) => {
    if (url === "/api/v1/keys") {
      const body = JSON.parse(init.body);
      keys.push({ ...body, idempotencyKey: init.headers["Idempotency-Key"] ?? null });
      if (keyStatus) return { status: keyStatus, json: async () => ({}) };
      return body.key === "="
        ? { status: 202, json: async () => ({ taskId: "t1" }) }
        : { status: 204, json: async () => ({}) };
    }
    const answer = polls[Math.min(pollIndex++, polls.length - 1)];
    return { status: answer.status, json: async () => answer.body };
  };
  return { fetchFn, keys, pollCount: () => pollIndex };
}

/**
 * Builds the page with fakes.
 *
 * Description: The bus is an `EventTarget`; timers are collected and run
 * by the test; every published `aaas:*` event is recorded.
 *
 * Business Justification: Exercises the page as the browser runs it.
 *
 * Errors: None.
 *
 * Side Effects: None outside the fakes.
 *
 * Complexity: O(1).
 *
 * Thread Safety: single-threaded tests.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @param {ReturnType<typeof fakeApi>} api The fake API.
 * @returns {object} The page, its fakes and helpers.
 * @since shell 0.1.0
 */
function setup(api) {
  const bus = new EventTarget();
  const main = { textContent: "" };
  const detail = { textContent: "" };
  const timers = [];
  const events = [];
  for (const name of ["aaas:clear", "aaas:task-started", "aaas:task-finished"]) {
    bus.addEventListener(name, (e) => events.push([name, e.detail]));
  }
  let n = 0;
  let clock = 0;
  const app = createApp({
    bus,
    main,
    detail,
    fetchFn: api.fetchFn,
    newId: () => `id-${n++}`,
    now: () => clock,
    setTimer: (callback, ms) => timers.push({ callback, ms }),
  });
  const pressKeys = (keys) => {
    for (const key of keys) bus.dispatchEvent(new CustomEvent("aaas:key-pressed", { detail: { key } }));
  };
  const tick = async (advanceMs = POLL_MS) => {
    clock += advanceMs;
    const due = timers.splice(0);
    for (const t of due) t.callback();
    await new Promise((resolve) => setTimeout(resolve, 0));
  };
  return { app, main, detail, timers, events, pressKeys, tick };
}

/**
 * Lets pending promises settle.
 *
 * Description: One macrotask turn.
 *
 * Business Justification: Awaits the fake requests.
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
 * @returns {Promise<void>} Resolves after the turn.
 * @since shell 0.1.0
 */
function settle() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

test("2+3= is sent in order, polled every second and shows 5", async () => {
  const counting = { status: 200, body: { taskId: "t1", status: "COUNTING", progress: { done: 1, total: 3 } } };
  const recorded = {
    status: 200,
    body: { taskId: "t1", status: "RECORDED", progress: { done: 3, total: 3 }, result: 5 },
  };
  const api = fakeApi([{ status: 404 }, counting, recorded]);
  const page = setup(api);
  assert.equal(page.main.textContent, "0");
  page.pressKeys("2+3=");
  assert.equal(page.main.textContent, "2+3");
  await page.app.idle();
  await settle();
  assert.deepEqual(
    api.keys.map((k) => [k.key, k.seq]),
    [
      ["2", 0],
      ["+", 1],
      ["3", 2],
      ["=", 3],
    ],
  );
  assert.ok(api.keys[3].idempotencyKey);
  assert.deepEqual(page.events[0], ["aaas:task-started", { taskId: "t1" }]);
  assert.equal(page.timers[0].ms, POLL_MS);
  await page.tick();
  assert.equal(page.detail.textContent, "COUNTING 1 / 3");
  await page.tick();
  assert.equal(page.main.textContent, "5");
  assert.equal(page.detail.textContent, "2+3 =");
  assert.deepEqual(page.events.at(-1), ["aaas:task-finished", { taskId: "t1", result: 5 }]);
  assert.equal(page.timers.length, 0, "polling stops after the result");
});

test("C publishes aaas:clear, resets the display and stops the old poll", async () => {
  const api = fakeApi([{ status: 404 }]);
  const page = setup(api);
  page.pressKeys("1+1=");
  await page.app.idle();
  await settle();
  page.pressKeys("C");
  assert.deepEqual(page.events.at(-1), ["aaas:clear", null]);
  assert.equal(page.main.textContent, "0");
  const polls = api.pollCount();
  await page.tick();
  assert.equal(api.pollCount(), polls, "the cleared task is not polled again");
});

test("an unreachable API shows Unavailable and stops sending that session", async () => {
  const api = fakeApi([{ status: 404 }], 503);
  const page = setup(api);
  page.pressKeys("12");
  await page.app.idle();
  assert.equal(page.main.textContent, "Unavailable");
  assert.equal(api.keys.length, 3, "three attempts for the first key, none for the second");
});
