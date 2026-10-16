# Contributing to AaaS

| Field | Value |
| --- | --- |
| Document | Contribution Guide |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Last Reviewed | 2026-10-16 |

Thank you for your interest in advancing the state of the art in integer
addition. This guide describes how a change travels from an idea to `main`.
The normative source is [`CLAUDE.md`](CLAUDE.md) (sections 6 to 9); this file
summarises it in English.

## 1. Before You Start

- Read [`docs/onboarding/ONBOARDING.md`](docs/onboarding/ONBOARDING.md) and the
  "Current State" block of [`docs/PROGRESS.md`](docs/PROGRESS.md).
- The product scope is fixed: a calculator keypad, a display, a waiting-time
  counter and an invoice download. Feature requests outside that scope are
  declined by policy (`CLAUDE.md` section 1).
- A change that spans more than one service needs an RFC
  ([`docs/governance/RFC_PROCESS.md`](docs/governance/RFC_PROCESS.md)); an
  architectural decision not covered by `CLAUDE.md` needs an ADR in
  [`docs/adr/`](docs/adr/).

## 2. Work Is Organised in Steps

Every change belongs to a step `P<phase>.<step>` of the plan (`CLAUDE.md`
9.3). Exactly one step is `IN_PROGRESS` at a time.

1. **Start**: branch `step/P<phase>.<step>-<short-description>` from `main`,
   set the step to `IN_PROGRESS` in `docs/PROGRESS.md`, create its log in
   `docs/progress/steps/` from `TEMPLATE.md`, commit
   `chore(progress): start P<phase>.<step>`.
2. **Work**: small commits, one logical change each. Document as you go.
3. **Interrupt** (if needed): commit `chore(progress): checkpoint ...` on the
   step branch and record "Next actions" in the step log.
4. **Close**: meet the Definition of Done (section 5), complete the log,
   commit `chore(progress): complete P<phase>.<step>`, merge into `main`
   with fast-forward or squash, tag `step/P<phase>.<step>`, push with tags.

## 3. Commit Messages

[Conventional Commits](https://www.conventionalcommits.org/) with the
repository rules enforced by commitlint (locally in the `commit-msg` hook, in
CI on every pushed range):

```
<type>(<scope>): <imperative description, lower case, no period>

<optional body: what and why>

Step: P<phase>.<step>
Refs: ADR-NNNN
```

- Types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`, `ci`,
  `chore`, `contract`, `infra`.
- Scope (mandatory, kebab-case): a service (`successor`), a frontend element
  (`frontend-key-3`) or an area (`compose`, `contracts`, `observability`,
  `aws`, `repo`, `progress`).
- Header at most 72 characters; exactly one `Step:` trailer.
- Contract changes (`contracts/`) are separate `contract(...)` commits.

## 4. Local Tooling

```sh
brew install pre-commit        # or: pip install pre-commit
pre-commit install --install-hooks
make help                      # every command
```

The hooks need Docker running (hadolint and actionlint run as containers).
Nothing else is installed on the host: every component builds, lints and
tests inside Docker through its own Makefile (ADR-0002).

| Command | Purpose |
| --- | --- |
| `make new-service NAME=<name> LANG=<language>` | Scaffold a service (ADR-0004) |
| `scripts/file-header.sh render ...` | Mandatory file header (ADR-0007) |
| `make build-<svc>` / `make test-<svc>` / `make lint-<svc>` | One component |
| `make lint` | Every linter, scaffold markers, `TEMPORARY` markers |
| `make doc-coverage` | File headers, documented definitions, native doc tools (ADR-0009) |
| `make up` / `make e2e` | Run the system / end-to-end tests |
| `make status` | Current state of the project |

## 5. Definition of Done

A step is done only when every item holds (`CLAUDE.md` 9.1). The pull request
template repeats this list as a checklist.

- `make build` (or `make build-<svc>`) passes; unit tests pass.
- `make up` starts everything expected at this stage with green healthchecks.
- `make e2e` passes if the step touches the addition flow.
- `make lint` passes; `make doc-coverage` is 100% for changed services.
- Service README, ADRs and the ten service documents (`CLAUDE.md` 6.5.5)
  are current; `make docs` builds without warnings.
- Everything in the repository is in English (only `CLAUDE.md` is Polish).
- The step-closing protocol (`CLAUDE.md` 8.1) is complete.

## 6. Documentation Standard

Every file starts with the header of `CLAUDE.md` 6.5.2 (render it with
`scripts/file-header.sh`). Every module, type, function and constant, public
and private, has a docstring with the fields of `CLAUDE.md` 6.5.3. Tone is
formal; content is true. A docstring that describes behaviour the code does
not have is a defect of the same severity as a bug.

## 7. Review and Merge

- `main` is always green; CI (`.github/workflows/ci.yml`, ADR-0006) must pass.
- Pull requests use the template in `.github/pull_request_template.md`; the
  title follows the commit format. Owners are assigned by `CODEOWNERS`.
- A solo maintainer may merge a step branch locally (fast-forward) without a
  pull request, as described in `CLAUDE.md` 7.2.
- History of `main` is never rewritten. A closed step is reverted by a new
  step or an ADR.

## 8. Code of Conduct and Security

Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).
Vulnerabilities are reported as described in [SECURITY.md](SECURITY.md).
