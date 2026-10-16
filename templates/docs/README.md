# Service document templates

Every service (`services/<name>/docs/`) and microfrontend
(`frontend/<element>/docs/`) carries the ten documents required by
`CLAUDE.md`, section 6.5.5. `scripts/new-service.sh` renders every
`*.md.tmpl` file of this directory into the new service's `docs/`.

| Template | Document |
| --- | --- |
| `SERVICE_CHARTER.md.tmpl` | Mission, business value, stakeholders, scope, KPIs |
| `RACI.md.tmpl` | RACI matrix for changes, deployments, incidents, migrations |
| `SLO.md.tmpl` | SLIs, SLOs, error budget, measurement window |
| `RUNBOOK.md.tmpl` | Every alert: meaning, diagnosis, remediation, escalation |
| `THREAT_MODEL.md.tmpl` | STRIDE threats, mitigations, residual risk |
| `DATA_CLASSIFICATION.md.tmpl` | Stored data, classification, retention |
| `DEPENDENCIES.md.tmpl` | Upstream and downstream dependencies and failure effects |
| `CAPACITY.md.tmpl` | Memory and CPU limits, measured usage |
| `API.md.tmpl` | Endpoints and events (generated from the contracts once they exist, ADR-0010) |
| `CHANGELOG.md.tmpl` | Keep a Changelog, SemVer per service, Business Impact |

## Placeholders

The templates use the placeholders of `templates/service/`, filled in from
the service catalog (`templates/service/catalog.psv`):

| Placeholder | Example |
| --- | --- |
| `__SERVICE__` | `successor` |
| `__SERVICE_UPPER__` | `SUCCESSOR` |
| `__LANGUAGE__` | `haskell` |
| `__TEAM__`, `__TEAM_ABBR__` | `Arithmetic Excellence Center`, `AEC` |
| `__DB__`, `__DB_KIND__` | `CouchDB`, `container` |
| `__PURPOSE__` | One sentence from the catalog |
| `__MEM__`, `__MEM_REASON__` | `64m`, justification from CLAUDE.md 6.2 |
| `__VERSION__` | `0.1.0` |
| `__DATE__` | Date of scaffolding, `YYYY-MM-DD` |

## Rules

- Content that holds for every service (platform conventions from
  `CLAUDE.md` 6.1 and 6.2, team, database, memory limit) is written out in
  the templates. Content that only the service's author knows is marked
  `TODO(scaffold)`; `make lint` fails while any marker remains, so a service
  cannot be completed with unfinished documents.
- Documentation must be true (`CLAUDE.md` 6.5): when a generic statement of a
  template does not hold for a service, change or remove it in that
  service's copy.
- Microfrontends use the same templates; replace the service-specific rows
  (database, ports) when the frontend is created in Phase 8.
