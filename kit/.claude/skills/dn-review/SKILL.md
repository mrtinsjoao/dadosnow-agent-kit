---
name: dn-review
description: Review the current changes with two fresh-context reviewers in parallel — dn-code-reviewer and dn-security-reviewer — and consolidate their findings into one PASS or BLOCK. Use before committing or opening a pull request, or when the user asks for a review.
---

# dn-review — two reviewers, one verdict

The reviewers did not write the code, so they read it the way a teammate
would. That is the point: independent review, not self-check.

## Steps

1. **Pick the diff.**
   - Uncommitted work: `git diff HEAD` (include untracked files the user
     mentions).
   - A branch: `git diff $(git merge-base HEAD origin/HEAD)...HEAD`, or the base
     branch the user names.
   If the diff is empty, say so and stop.
2. **Launch both reviewers in the same message**, so they run in parallel:
   `dn-code-reviewer` and `dn-security-reviewer`. Give each the diff and the
   list of changed files. Do not add your own opinion of the code to their
   prompt.
3. **Consolidate.** Merge duplicate findings, keep the highest severity, sort
   P1 → P3. Drop anything a reviewer reported that you can show is wrong by
   reading the file, and say that you dropped it.
4. **Report**:

   ```
   VERDICT: PASS | BLOCK
   - [P1] ... — path:line (reviewer)
   - [P2] ...
   ```

   BLOCK when any P1 survives. Then stop: fixing is a separate step the user
   decides.

## Rules

- This review was asked for. Don't start further review rounds or launch
  more reviewers on your own; if a deeper review looks worth it, say so.
- The pre-push gate runs the same two reviewers automatically. `/dn-review`
  is for earlier feedback, while the change is still cheap to fix.
