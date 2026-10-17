# ADR-0013: Event envelope, schema conventions and contract tests

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-17 |
| Deciders | Platform Enablement Guild (PEG), Transaction Integrity Office (TIO) |
| Step | P1.3 |

## Context

`CLAUDE.md` 4.2 fixes the envelope of every event (`eventId`, `type`,
`version`, `occurredAt`, `producer`, `taskId`, `traceparent`, `payload`),
JSON as the format, JSON Schema as the contract language with source files
in `contracts/events/`, immutable events and a new `.v<N+1>` topic for every
incompatible change. Section 6.4 requires the examples to be validated in CI.
Section 3 (step 10) defines the ledger hash as
`sha256(prevHash || taskId || a || b || result || timestamp)`.

The specification leaves open: the JSON Schema dialect, the exact format of
identifiers and timestamps, how an event schema reuses the envelope, which
payload fields the four first events carry, how schemas may evolve inside
one version, the byte encoding of the ledger hash, and what the contract
test proves.

## Decision

- **Dialect and identity.** JSON Schema 2020-12. Every schema has an `$id`
  of the form `urn:aaas:events:<topic>` (`urn:aaas:events:envelope:v1` for
  the envelope), a `title` equal to the topic name and a `description`.
  URNs avoid inventing a domain; the schema registry (P3.1) stores the
  documents under their topic. Ownership and classification, which JSON
  cannot carry in a comment, are recorded in the `$comment` keyword.
- **Layout.** `envelope.v1.schema.json`, one `<topic>.schema.json` per
  event, and examples in `examples/<topic>/valid/*.json` (raw events) and
  `examples/<topic>/invalid/*.json` (test cases
  `{"description", "errorAt", "event"}`).
- **Envelope as the base.** An event schema is `allOf: [{"$ref":
  "urn:aaas:events:envelope:v1"}]` plus `const` values for `type`,
  `version` and `producer` (the producer of `topics.psv`), a non-null
  `taskId` and a closed payload. Shared types (`uuidV7`, `timestamp`,
  `operand`, `sum`, `sha256`) live in the envelope's `$defs`.
- **Formats.**
  - `eventId` and `taskId` are lowercase UUIDv7 (RFC 9562): time-ordered,
    as `CLAUDE.md` 3 already requires for `taskId`.
  - `taskId` may be `null` in the envelope only for an event that precedes
    the task (`aaas.key.pressed.v1`, P1.4, keyed by session); every event
    with a schema in this step narrows it to a UUID.
  - Timestamps are UTC with exactly three fractional digits and `Z`
    (`2026-10-16T12:00:00.000Z`), enforced by a pattern, and the
    `date-time` format is asserted, so impossible dates fail. The fixed
    form keeps hashes over timestamps reproducible across 28 languages.
  - `traceparent` follows W3C Trace Context version `00`, lowercase, and
    rejects all-zero trace and parent identifiers.
- **Closed schemas, tolerant consumers.** The envelope and every payload set
  `additionalProperties: false`, so a producer that misspells a field fails
  validation (producers validate before publishing from P3.1). Consumers do
  not reject events for unknown fields (tolerant reader). Adding an
  *optional* payload field is therefore a compatible change made in the
  existing schema; adding a required field, removing or renaming a field,
  or narrowing a type is incompatible and creates a new `.v<N+1>` topic.
- **Payloads of the first four events.**

  | Event | Payload |
  | --- | --- |
  | `aaas.expression.submitted.v1` | `sessionId` (UUID), `expression` (`^[0-9+]{1,64}$`, the key presses before `=`) |
  | `aaas.addition.requested.v1` | `a`, `b` (0–99 999), exactly the example of `CLAUDE.md` 4.2 |
  | `aaas.result.voted.v1` | `a`, `b`, `result` (0–199 998) |
  | `aaas.ledger.appended.v1` | `sequence` (≥ 1), `a`, `b`, `result`, `recordedAt`, `prevHash`, `hash` |

  The syntax of an expression is checked by `parser` and the operand range
  by `validator`, so `expression.submitted` accepts any sequence of digit
  and `+` keys; a malformed expression is a valid event that the parser
  rejects. `ledger.appended` carries the whole entry so that `cloud-notary`
  (P10.3) verifies the chain from the event alone. Vote details
  (`CLAUDE.md` 4.3, `votes`) and the idempotency key needed for
  compensation (P6.3) are added later as optional fields under the policy
  above.
- **Ledger hash encoding.** `hash = sha256(UTF-8("prevHash|taskId|a|b|result|recordedAt"))`
  in lowercase hexadecimal; numbers in decimal without leading zeros,
  `taskId` and `recordedAt` exactly as in the event, and `prevHash` of the
  first entry is 64 zeros. The `|` separator refines the `||`
  concatenation of `CLAUDE.md` 3: plain concatenation is ambiguous
  (`a = 1, b = 11` and `a = 11, b = 1` both give `1112`), and an ambiguous
  input would let two different additions share a hash.
- **Contract test.** `scripts/validate-events.py`, run by
  `make contracts-check` (part of `make lint`) and by the CI job
  `contracts`, checks every schema against the 2020-12 meta-schema and the
  rules above (naming, `$id`, registry and producer, `const` values,
  envelope reference, a `description` on every property), requires at
  least one valid and one invalid example per event, passes every valid
  example, and fails every invalid one **at the JSON pointer given in
  `errorAt`**, so that a negative example cannot pass by failing for an
  unintended reason. Valid examples must also be true: `result = a + b`
  and the ledger hash follows the rule above. The tool runs in the
  documentation tool image (`infra/docs-portal`), which pins `jsonschema`
  and its dependencies; the portal's event catalog renders the fields of
  every schema from the same files.

## Consequences

- Services implement against fixed, documented payloads and can reuse the
  valid examples as test fixtures.
- Every producer must emit UUIDv7 identifiers and millisecond UTC
  timestamps; languages without a UUIDv7 library need a small helper.
- Producers whose events are rejected by a closed schema fail fast; the cost
  is that every new field needs a schema change first (a `contract`
  commit), which is the intent of `CLAUDE.md` 7.
- The hash rule differs in notation from `CLAUDE.md` 3; `CLAUDE.md` now
  points to this ADR.
- Schema compatibility is checked by review and by this policy until the
  schema registry enforces it (P3.1).
