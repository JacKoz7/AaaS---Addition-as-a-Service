# Data Protection Impact Assessment (DPIA)

| Field | Value |
| --- | --- |
| Document | Data Protection Impact Assessment (GDPR Art. 35) |
| Owning Team | Trust & Identity Board (TIB) |
| Classification | INTERNAL |
| Last Reviewed | 2026-10-16 |
| Review Trigger | Any step that adds a data store, an identifier or a log field (in particular P1.4, P6.1, P7.1, P10.3) |

## 1. Summary

AaaS processes two integers, their sum and the identifiers needed to deliver
the sum to the right browser session. It runs locally on its owner's
workstation; the only data leaving the host is a copy of ledger entries sent
to the owner's own AWS account (Phase 10). The assessment concludes that the
processing is of **low risk** to data subjects, provided the measures in
section 5 are implemented.

At the time of this review (Phase 0) no service exists and no personal data
is processed. The inventory below describes the data the planned services
will process; each service's `DATA_CLASSIFICATION.md` is authoritative once
the service exists.

## 2. Description of Processing

| Data Item | Personal Data | Introduced | Stored In | Purpose |
| --- | --- | --- | --- | --- |
| Operands `a`, `b` and result | No | P1.4 | expression-assembler, ledger, saga, consensus, billing, cloud-notary | Performing the addition |
| Key presses with `sessionId` and `seq` | Pseudonymous | P1.4 | expression-assembler (SurrealDB) | Assembling the expression of one browser session |
| `taskId` (UUIDv7) | No, unless joined with a session | P1.4 | Most services | Correlating one addition across services |
| Guest account and JWT subject | Pseudonymous | P6.1 | auth (Keycloak) | Authentication and per-user rate limits |
| Rate-limit counters per user | Pseudonymous | P6.2 | rate-limiter (Redis) | Abuse protection |
| Client IP address in gateway logs | Personal | P1.2 / P7.1 | Loki | Security and troubleshooting |
| Invoice PDF (0.00 PLN, fictitious seller, no buyer data) | No | P9.2 | billing (Firebird) | Humorous receipt |
| Ledger copy | No | P10.3 | AWS DynamoDB (owner's account) | Independent verification of the hash chain |

## 3. Necessity and Proportionality

- Only pseudonymous identifiers are used; no name, e-mail address or other
  contact data is collected. Guest login requires no registration.
- Operands and results are not personal data.
- Data is retained only as long as the local volumes exist; `make clean`
  erases every volume.

## 4. Risks to Data Subjects

| Risk | Likelihood | Severity | Assessment |
| --- | --- | --- | --- |
| Linking a session to a person through IP addresses in logs | Low | Low | Logs are local to the host |
| Disclosure of JWTs or session IDs | Low | Low | Tokens are short-lived; never logged (each service's `DATA_CLASSIFICATION.md`) |
| Transfer to AWS | Low | Low | Ledger entries contain no identifiers of persons |

## 5. Measures

- CONFIDENTIAL values (credentials, tokens) are never written to logs.
- Log retention in Loki is limited (to be set in P7.1 and recorded here).
- Each service documents its data and retention in `DATA_CLASSIFICATION.md`.
- Databases are reachable only by their own service (`data` network,
  `CLAUDE.md` 6.2).

## 6. Conclusion

Residual risk: Low. Processing may proceed. This assessment is revisited in
the steps listed under "Review Trigger".
