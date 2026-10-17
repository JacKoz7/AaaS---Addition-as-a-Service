// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       frontend-shell
// Module:          src/ids.js
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Random UUIDs (version 4) for session identifiers and
//                  idempotency keys, also outside a secure context.
// Related Docs:    RFC 9562, frontend/shell/README.md, ADR-0018

/**
 * UUID generation.
 *
 * Description: `crypto.randomUUID` exists only in secure contexts (HTTPS
 * or `localhost`); a page opened as `http://<host>/` from another machine
 * does not have it. `crypto.getRandomValues` is available everywhere, so
 * the UUID is built from 16 random bytes with the version and variant
 * bits of RFC 9562 (version 4).
 *
 * Business Justification: Every session and every `=` needs a fresh
 * identifier, whichever address the calculator is opened at.
 *
 * Thread Safety: browser main thread.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @module ids
 * @since shell 0.1.0
 */

/**
 * Formats 16 bytes as a version 4 UUID.
 *
 * Description: Sets the version nibble to `4` and the variant bits to
 * `10`, then writes lowercase hexadecimal in the 8-4-4-4-12 form. The
 * input is not modified.
 *
 * Business Justification: Separated from {@link randomUuid} so that the
 * layout is tested with fixed bytes.
 *
 * Errors: None (missing bytes count as 0).
 *
 * Side Effects: None.
 *
 * Complexity: O(1).
 *
 * Thread Safety: pure.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @param {Uint8Array} bytes Sixteen random bytes.
 * @returns {string} The UUID.
 * @since shell 0.1.0
 * @example
 * uuidV4FromBytes(new Uint8Array(16)); // "00000000-0000-4000-8000-000000000000"
 */
export function uuidV4FromBytes(bytes) {
  const b = Array.from({ length: 16 }, (_, i) => bytes[i] ?? 0);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const hex = b.map((x) => x.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/**
 * A new random version 4 UUID.
 *
 * Description: 16 bytes from `getRandomValues`, formatted by
 * {@link uuidV4FromBytes}.
 *
 * Business Justification: See the module documentation.
 *
 * Errors: None in a browser (`getRandomValues` is always available).
 *
 * Side Effects: reads the random source.
 *
 * Complexity: O(1).
 *
 * Thread Safety: browser main thread.
 *
 * Owner: Customer Experience Tribe (CXT).
 *
 * @param {{getRandomValues: function(Uint8Array): Uint8Array}} [source] The random source.
 * @returns {string} The UUID.
 * @since shell 0.1.0
 * @example
 * randomUuid(); // for example "3f1c2a9e-7b4d-4e21-9a0f-5c6d7e8f9012"
 */
export function randomUuid(source = globalThis.crypto) {
  return uuidV4FromBytes(source.getRandomValues(new Uint8Array(16)));
}
