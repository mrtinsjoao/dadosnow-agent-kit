# Changelog

## 0.1.0 — 2026-10-01

First public version.

- `install.sh` / `uninstall.sh`: additive, idempotent, backup on `--force`,
  appends to existing or Husky `pre-push` hooks.
- Skills: `dn-init` (adapts the kit to the repository), `dn-plan`, `dn-tdd`,
  `dn-review`.
- Read-only subagents: `dn-explorer`, `dn-code-reviewer`, `dn-security-reviewer`
  (Claude Code `sonnet` alias, Claude Sonnet 5.5 as of 2026-09-30).
- Pre-push review gate: two reviewers in parallel, blocks only on P1 (exit
  code 10), fail-open otherwise; works without `timeout` (macOS), on new
  branches, force pushes and deletions; `DN_GATE`, `DN_GATE_MAX_LINES`,
  `DN_GATE_TIMEOUT`.
- `.dadosnow/models.yaml` with model tiers, prices and the activity matrix,
  verified 2026-09-30.
- `examples/demo-app` end-to-end walkthrough.
- `tests/test_kit.sh`: 19 end-to-end tests with a stub `claude` (install,
  idempotency, `--force`, existing and non-shell hooks, `core.hooksPath`,
  blocking, fail-open cases, branch deletion, uninstall).
