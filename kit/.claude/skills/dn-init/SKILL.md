---
name: dn-init
description: Adapt the DadosNow kit to this repository. Reads the stack, commands and sensitive paths, drafts AGENTS.md, CLAUDE.md and .dadosnow/SPEC.md, shows the draft and writes only after the user approves. Use right after install.sh, or when the project's stack or rules change.
---

# dn-init — fit the kit to this repository

You are turning generic templates into this project's own instructions. The
result is read by every future session and subagent, so it must be short,
true and specific.

## Steps

1. **Read the repository, don't guess.** Look for, at the root and one level
   down:
   - manifests: `package.json`, `pnpm-lock.yaml`, `yarn.lock`, `pyproject.toml`,
     `requirements*.txt`, `go.mod`, `Cargo.toml`, `pom.xml`, `build.gradle*`,
     `Gemfile`, `composer.json`, `Dockerfile`, `docker-compose*.yml`;
   - commands: `scripts` in `package.json`, `Makefile` targets, `justfile`,
     `tox.ini`, CI workflows under `.github/workflows/`;
   - conventions: linters and formatters configured, test folders, `src/` vs
     flat layout, monorepo workspaces;
   - sensitive paths: migrations, auth, billing/payments, infra, `.env*`,
     secrets managers, anything under `prod`.
   For a large repo, delegate the reading to the `dn-explorer` subagent.

2. **Draft three files** from the templates in `.dadosnow/`:
   - `AGENTS.md` from `.dadosnow/AGENTS.template.md` — stack, exact commands
     (install, dev, test, lint, build), conventions, the "never do" list, and
     the activity → model × effort matrix. Keep it under 150 lines.
   - `CLAUDE.md` containing only the line `@AGENTS.md`. If a `CLAUDE.md`
     already exists, keep it and propose adding `@AGENTS.md` at the top.
   - `.dadosnow/SPEC.md` from `.dadosnow/SPEC.template.md` — tiers per
     activity, the paths that always stop for the owner, the monthly budget
     (leave a placeholder if unknown).
   Fill every field from what you found. Mark anything you inferred rather
   than read with `(inferred)`. Do not invent commands.

3. **Show the draft and stop.** Print the three files (or a diff when a file
   already exists) and ask the user to approve or edit. Write nothing before
   the approval.

4. **Write and confirm.** After approval, write the files and run one real
   command from the new AGENTS.md (the test or lint command) to prove it
   works. Report what ran and its result. If it fails because dependencies
   are missing, say so; do not install anything unless the user asks.

## Rules

- Never overwrite an existing `AGENTS.md`, `CLAUDE.md` or `SPEC.md` without
  showing the diff and getting a yes.
- `AGENTS.md` is the single source of instructions. Codex, Cursor and other
  harnesses read it too, so keep Claude-specific notes out of it; they belong
  in `CLAUDE.md` below the import line.
- If the repository is empty or has no recognizable stack, say so and ask
  what it will be instead of producing a generic file.
