# Changelog

## 0.2.0 — 2026-10-11

- Claude Haiku 5.5 (`claude-haiku-5-5`) for bounded work. `models.yaml`
  gains a tiered price (prompt up to / over 100K tokens), 1M context and
  effort default `medium`, verified 2026-10-11. Haiku agents name the full ID
  because the `haiku` alias still resolved to Haiku 4.5 on Claude Code 2.1.291.
- New `dn-git-ops` subagent: runs one git operation fully specified by the
  caller (commit listed files, push a named branch, open a PR). Push and PR
  need `USER_AUTHORIZED_PUSH: yes` with the user's words. It never pushes to
  the default branch, never uses `--force`/`--no-verify`, never merges and
  refuses secret-looking paths and lines.
- New `dn-monitor` subagent: read-only CI runs, open PRs (via `gh`) and gate
  results.
- `dn-explorer` moves from Sonnet to Haiku 5.5 (effort `medium`).
- The gate appends one JSON line per run to `.git/dadosnow/gate.jsonl`.
- `install.sh` writes `.dadosnow/manifest` (hash per installed file). A
  later install updates every file still unchanged since it was installed,
  without `--force`. In 0.1.0, any file the kit had changed counted as
  user-edited and was kept. Upgrading from 0.1.0 needs `--force` once.
  `uninstall.sh` uses the same manifest.
- GitHub Actions runs `tests/test_kit.sh` on every push and PR. Tests: 26.
- README in English with a Portuguese translation (`README.pt-BR.md`):
  requirements, a real BLOCK transcript, measured gate cost and time, new FAQ.

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
