# AGENTS.md — dadosnow-agent-kit

Instructions for agents working on the kit itself (not on a project that
uses it).

## Layout
- `kit/` — everything that gets copied into a user's project. Paths inside
  mirror the destination (`kit/.claude/agents/x.md` -> `<project>/.claude/agents/x.md`).
- `install.sh`, `uninstall.sh` — bash, no dependencies beyond git and coreutils.
- `examples/demo-app/` — the end-to-end demo; keep it dependency-free.
- `README.md` — user-facing docs in Portuguese (pt-BR). Code, skills, agents
  and commit messages are in English.

## Commands
| Purpose | Command |
|---|---|
| Syntax check scripts | `bash -n install.sh uninstall.sh kit/.dadosnow/gate.sh` |
| Kit tests (stub claude, free) | `bash tests/test_kit.sh` |
| Demo tests | `cd examples/demo-app && python3 -m unittest -q` |
| End-to-end | follow `examples/demo-app/README.md` in a throwaway dir |

## Rules
- The kit must stay additive: never overwrite a user's file without `--force`,
  and always back it up first.
- The gate must stay fail-open: only an explicit `VERDICT: BLOCK` blocks.
- Subagents are read-only (`Read, Grep, Glob`).
- Skill frontmatter uses only `name` and `description` (portable across
  harnesses).
- No references to private projects, clients, IPs or personal paths.
- Before reporting a change done, run the syntax check and the end-to-end
  demo for what you touched.
