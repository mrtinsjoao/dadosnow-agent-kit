---
name: dn-tdd
description: Implement a change test-first — red, green, refactor — using the project's own test command from AGENTS.md. Use when adding or changing behavior in code that has, or can have, automated tests.
---

# dn-tdd — red, green, refactor

## Cycle

1. **Red.** Write one test for the next small piece of behavior. Run it with
   the project's test command and see it fail for the expected reason. A test
   that passes before the code exists is testing nothing.
2. **Green.** Write the least code that makes it pass. Run the test again.
3. **Refactor.** Clean up names and duplication with the tests green. Run the
   whole relevant suite.

Repeat until the requested behavior is covered.

## Rules

- One behavior per test; the test name says what it guarantees.
- Test behavior through the public interface, not private details.
- Use the test command from `AGENTS.md`. If there is none, ask before adding
  a test framework.
- **A real check before "done."** Before reporting the work done, run a check
  that exercises the change: the project's tests, type-checker or build. A
  syntax-only check, or a test command that failed to start, does not count.
  If the only thing missing is the project's declared dependencies, install
  them with its own package manager and lockfile — never with sudo or the
  system package manager — unless told not to. If no real check can run here,
  say which one you did not run and why instead of reporting it done.
- When the requested work is done and its checks pass, stop and report. Don't
  add features, extra test suites, docs or refactors that were not asked for;
  mention them at the end instead.

## When not to use

Throwaway spikes, pure configuration, and generated code. Say so explicitly
when you skip the cycle.
