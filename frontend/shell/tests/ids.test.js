// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       frontend-shell
// Module:          tests/ids.test.js
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Unit tests of the UUID generator.
// Related Docs:    frontend/shell/src/ids.js, RFC 9562, ADR-0018

import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUuid, uuidV4FromBytes } from "../src/ids.js";

test("version and variant bits are set", () => {
  assert.equal(uuidV4FromBytes(new Uint8Array(16).fill(0xff)), "ffffffff-ffff-4fff-bfff-ffffffffffff");
  assert.equal(uuidV4FromBytes(new Uint8Array(16)), "00000000-0000-4000-8000-000000000000");
});

test("random UUIDs are well formed and distinct", () => {
  const seen = new Set();
  for (let i = 0; i < 100; i++) {
    const id = randomUuid();
    assert.match(id, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
    seen.add(id);
  }
  assert.equal(seen.size, 100);
});

test("the random source is injectable", () => {
  const source = { getRandomValues: (a) => a.fill(1) };
  assert.equal(randomUuid(source), "01010101-0101-4101-8101-010101010101");
});
