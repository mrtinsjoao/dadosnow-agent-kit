# AGENTS.md — <project name>

Instructions for coding agents working in this repository. Keep this file
short and true: every session and every subagent reads it.

## Stack
- Language / runtime: <e.g. TypeScript 5 on Node 22>
- Frameworks: <e.g. Next.js 15, Prisma>
- Package manager: <e.g. pnpm>

## Commands
| Purpose | Command |
|---|---|
| Install | `<command>` |
| Dev server | `<command>` |
| Test | `<command>` |
| Lint / type-check | `<command>` |
| Build | `<command>` |

## Conventions
- <layout: where code, tests and configs live>
- <style rules the linter does not enforce>
- <commit message format>

## Never do
- Commit secrets, `.env` files or credentials.
- Push to the default branch directly.
- Run destructive commands (drop tables, `rm -rf`, force-push) without asking.
- <project-specific rule>

## Paths that always stop for the owner
See `.dadosnow/SPEC.md`. Summary: <migrations, auth, billing, infra, prod config>.

## Working method
- Plan before multi-file changes (`/dn-plan`), test-first for behavior
  (`/dn-tdd`), review before commit (`/dn-review`).
- Heavy reading goes to a read-only subagent; keep the main session for
  decisions.
- Before reporting code done, run a real check that exercises it.
- When the requested work is done and checked, stop and report. Suggest
  extras at the end instead of doing them.

## Activity → model × effort
| Activity | Model | Effort |
|---|---|---|
| Explore the codebase | sonnet | medium |
| Implement a known pattern | sonnet | medium |
| Implement something hard | sonnet | high |
| Review a diff | sonnet | high |
| Architecture or risky change | opus | high |
| Chores, renames | haiku | — |
