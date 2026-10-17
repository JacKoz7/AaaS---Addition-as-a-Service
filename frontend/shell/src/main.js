// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       frontend-shell
// Module:          src/main.js
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Entry point of the temporary page: builds the keypad and
//                  starts the page logic with the browser's window, document
//                  and fetch.
// Related Docs:    frontend/shell/README.md, ADR-0018

/**
 * Browser entry point.
 *
 * Description: Renders one button per key of {@link module:calculator.KEYS}
 * into `#keypad`; a click publishes `aaas:key-pressed {key}` on `window`
 * (CLAUDE.md 2), which {@link module:app.createApp} consumes. Loaded by
 * `index.html` as an ES module.
 *
 * TEMPORARY(P8.15): replaced by the single-spa shell and the key
 * microfrontends of Phase 8.
 *
 * Business Justification: The keypad of CLAUDE.md 1.
 *
 * Thread Safety: browser main thread.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @module main
 * @since shell 0.1.0
 */

import { KEYS } from "./calculator.js";
import { createApp } from "./app.js";
import { randomUuid } from "./ids.js";

/**
 * Builds the keypad buttons.
 *
 * Description: One `<button>` per key with `data-key`; `=` and `C` get a
 * class for their colour.
 *
 * Business Justification: The only input of AaaS.
 *
 * Errors: None.
 *
 * Side Effects: appends elements to `container`; adds click listeners.
 *
 * Complexity: O(number of keys).
 *
 * Thread Safety: browser main thread.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @param {HTMLElement} container The keypad element.
 * @returns {void}
 * @since shell 0.1.0
 * @example
 * buildKeypad(document.getElementById("keypad"));
 */
export function buildKeypad(container) {
  for (const key of KEYS) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = key;
    button.dataset.key = key;
    button.setAttribute("aria-label", key === "C" ? "Clear" : key === "=" ? "Equals" : key === "+" ? "Plus" : key);
    if (key === "=") button.classList.add("equals");
    if (key === "C") button.classList.add("clear");
    button.addEventListener("click", () => {
      window.dispatchEvent(new CustomEvent("aaas:key-pressed", { detail: { key } }));
    });
    container.append(button);
  }
}

buildKeypad(document.getElementById("keypad"));
createApp({
  bus: window,
  main: document.getElementById("display-main"),
  detail: document.getElementById("display-detail"),
  fetchFn: window.fetch.bind(window),
  newId: () => randomUuid(),
  now: () => Date.now(),
  setTimer: (callback, ms) => window.setTimeout(callback, ms),
});
