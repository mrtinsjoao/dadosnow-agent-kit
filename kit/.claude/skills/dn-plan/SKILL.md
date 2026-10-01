---
name: dn-plan
description: Write a short implementation plan before touching code — goal, files, steps with a check each, risks — and stop for approval. Use for any change that touches more than two files, a schema, an API contract or a sensitive path from .dadosnow/SPEC.md.
---

# dn-plan — think on paper, then build

A plan is cheap; a wrong change in five files is not. This skill produces a
plan the user can approve in under a minute.

## Steps

1. **Understand before planning.** Read the code the change touches. For
   wide questions, send the `dn-explorer` subagent and keep only its report.
2. **Check `.dadosnow/SPEC.md`.** If the change touches a path listed under
   "always stops for the owner", say so at the top of the plan.
3. **Write the plan** in this shape:

   ```
   GOAL: <one sentence, in the user's terms>

   FILES:
   - path/to/file — what changes

   STEPS:
   1. <change> — check: <the real command or test that proves it>
   2. ...

   RISKS: <what could break and how we would notice, or "none">
   OUT OF SCOPE: <what this plan deliberately does not do>
   ```

4. **Stop.** Ask for approval. Do not start building in the same turn.

## Rules

- Every step has a check that actually runs: a test, a build, a type-check or
  the changed command. "Review the code" is not a check.
- Prefer the smallest plan that reaches the goal. No refactors, abstractions
  or extra features nobody asked for; if one would help, list it under
  OUT OF SCOPE.
- When the user asks for ideas, options or a plan, give that and stop.
