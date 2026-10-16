# Postmortem: <Short Title>

<!--
Blameless postmortem template. Copy to docs/governance/postmortems/
YYYY-MM-DD-short-title.md for every SEV1 and SEV2 incident (severity levels
are defined in the incident issue form). Describe systems and decisions, not
people: the question is what allowed the failure, never who caused it.
-->

| Field | Value |
| --- | --- |
| Incident | #<issue number> |
| Severity | SEV1 / SEV2 |
| Status | Draft / Reviewed / Actions complete |
| Date of Incident | YYYY-MM-DD |
| Duration | HH:MM (detection to resolution) |
| Author | <team> |
| Affected Services | <service>, <service> |

## Summary
Two or three sentences: what happened, what the impact was, how it ended.

## Impact
Additions affected (count, task IDs), wrong results recorded (if any),
ledger integrity, waiting time, cost.

## Timeline
All times with time zone.

| Time | Event |
| --- | --- |

## Root Cause
The technical cause and the conditions that allowed it. Use "five whys".

## Detection
How the incident was noticed (alert, test, user) and how it could have been
noticed earlier.

## Resolution
What restored service and why it worked.

## What Went Well

## What Went Poorly

## Action Items
| Action | Type (prevent / detect / mitigate) | Owner | Step | Status |
| --- | --- | --- | --- | --- |

## Risk Register
New or updated entries in `docs/governance/RISK_REGISTER.md`.
