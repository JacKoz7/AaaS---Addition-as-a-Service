# ADR-0005: Pre-commit hook set and commit message enforcement

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-16 |
| Deciders | Platform Enablement Guild (PEG) |
| Step | P0.5 |

## Context

`CLAUDE.md` 7.1 requires Conventional Commits with the `Step:` trailer and
names commitlint, hadolint, yamllint, shellcheck and a line-ending check as
pre-commit checks. The repository will contain Dockerfiles, YAML (Compose, CI,
contracts) and shell scripts from the first phase on; 28 language toolchains
will follow, and none of them should have to be installed on the host for the
hooks to work.

## Decision

- The **pre-commit framework** manages the hooks. Each hook's tool is
  installed by pre-commit into its own environment: yamllint (Python),
  shellcheck (`shellcheck-py`, bundled binary), commitlint (Node), hadolint
  (`hadolint-docker`, runs the official image through Docker). The only host
  prerequisites are `pre-commit`, Docker and Node (already required by the
  frontend work).
- Hook types installed by default: `pre-commit` and `commit-msg`
  (`default_install_hook_types`), so `pre-commit install` alone wires both.
- **Line endings**: `mixed-line-ending --fix=lf` in the hooks and
  `* text=auto eol=lf` in `.gitattributes`, so LF is enforced both at commit
  time and at checkout on every operating system.
- **Commit messages**: `commitlint.config.cjs` spells out the
  `@commitlint/config-conventional` rules and tightens them to the eleven
  types from `CLAUDE.md` 7.1, a mandatory kebab-case scope, a subject that
  must not start with a capital letter, a 72-character header, and a custom
  rule `aaas-step-trailer` that requires exactly one `Step: P<phase>.<step>`
  line (sub-steps such as `P2.13a` allowed). `extends` is not used because
  commitlint resolves it from the repository directory, not from the
  isolated hook environment, so the shared preset is unavailable there. The
  built-in `trailer-exists` rule was rejected because it checks only the key,
  not the value format.
- **Branch protection**: `no-commit-to-branch` blocks direct commits to
  `main`. Steps are merged with fast-forward, which the hook does not run on,
  so the step-closing protocol is unaffected. Hotfix commits on `main` require
  `--no-verify` and a justification in the step log.
- **hadolint**: `failure-threshold: warning`; `DL3006` (untagged image) and
  `DL3007` (`latest`) are promoted to errors because `CLAUDE.md` 6.2 forbids
  unpinned base images. Template files (`*.tmpl`) are not scanned; the
  rendered Dockerfile of each service is.
- **yamllint**: `extends: default` with `document-start` disabled, line length
  120, flow sequences allowed (`networks: [services, data]`), `on`/`off`
  accepted as values for GitHub Actions.
- **shellcheck**: `--severity=style --external-sources`; style findings fail
  the commit so that scripts stay uniform.
- `make lint-repo` runs `pre-commit run --all-files`; CI (P0.6) runs the same
  command plus commitlint over the pull request's commit range.

## Consequences

- A contributor cannot commit an unpinned base image, a CRLF file, a script
  with shellcheck findings or a commit message without a `Step:` trailer.
- Hooks need Docker running (for hadolint) and network access on first use to
  build the hook environments; `pre-commit install --install-hooks` warms them.
- `pre-commit autoupdate` is the only sanctioned way to bump hook versions and
  is run as a `chore(repo)` commit.
