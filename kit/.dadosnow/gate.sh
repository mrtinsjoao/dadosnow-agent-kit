#!/usr/bin/env bash
# DadosNow kit — pre-push review gate.
#
# Runs dn-code-reviewer and dn-security-reviewer (read-only Claude Code
# subagents) on the commits being pushed. Blocks the push only when a
# reviewer returns "VERDICT: BLOCK". Everything else is fail-open: no Claude
# Code, an error, a timeout or a diff that is too large lets the push through
# with a warning.
#
#   DN_GATE=off            skip the gate for one push
#   DN_GATE_MAX_LINES=N    skip diffs larger than N changed lines (default 3000)
#   DN_GATE_TIMEOUT=S      seconds per reviewer (default 600)
#
# Called by the pre-push hook with the hook's stdin; also works without it.
# Exit codes: 0 = allow, 10 = blocked by a reviewer. The hook blocks only on
# 10, so a crash or a broken interpreter can never block a push.

set -uo pipefail

say() { printf '[dn-gate] %s\n' "$*" >&2; }

[[ "${DN_GATE:-on}" == "off" ]] && { say "skipped (DN_GATE=off)"; exit 0; }
command -v claude >/dev/null 2>&1 || { say "Claude Code not found — push allowed without review"; exit 0; }

ROOT="$(git rev-parse --show-toplevel)" || exit 0
cd "$ROOT" || exit 0

ZERO="0000000000000000000000000000000000000000"
MAX_LINES="${DN_GATE_MAX_LINES:-3000}"
TIMEOUT="${DN_GATE_TIMEOUT:-600}"
TIMEOUT_CMD=()
if command -v timeout >/dev/null 2>&1; then TIMEOUT_CMD=(timeout "$TIMEOUT")
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_CMD=(gtimeout "$TIMEOUT")
else say "no timeout command found (install coreutils for one) — reviewers run without a time limit"; fi
EXCLUDES=(':(exclude)*.lock' ':(exclude)package-lock.json' ':(exclude)pnpm-lock.yaml' ':(exclude)yarn.lock')

default_base() {  # merge-base of $1 with the remote default branch, if one is known
  local head
  for head in "$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)" origin/main origin/master; do
    [[ -n "$head" ]] && git rev-parse -q --verify "$head" >/dev/null && { git merge-base "$1" "$head" 2>/dev/null; return; }
  done
}

# 1. Work out which ranges are being pushed.
RANGES=(); SAW_REFS=0
if [[ ! -t 0 ]]; then
  while read -r _lref lsha _rref rsha; do
    [[ -z "${lsha:-}" ]] && continue
    SAW_REFS=1
    [[ "$lsha" == "$ZERO" ]] && continue                               # branch deletion: nothing to review
    if [[ "$rsha" == "$ZERO" ]]; then base="$(default_base "$lsha")"   # new branch
    elif git merge-base --is-ancestor "$rsha" "$lsha" 2>/dev/null; then base="$rsha"
    else base="$(git merge-base "$rsha" "$lsha" 2>/dev/null || default_base "$lsha")"; fi   # force push
    [[ -n "$base" ]] && RANGES+=("$base..$lsha")
  done
fi
if [[ ${#RANGES[@]} -eq 0 && $SAW_REFS -eq 1 ]]; then say "nothing to review in this push"; exit 0; fi
if [[ ${#RANGES[@]} -eq 0 ]]; then                                     # no ref list on stdin — fall back
  if git rev-parse -q --verify '@{u}' >/dev/null; then RANGES=("@{u}..HEAD")
  else base="$(default_base HEAD)"; [[ -n "$base" ]] && RANGES=("$base..HEAD"); fi
fi
[[ ${#RANGES[@]} -eq 0 ]] && { say "could not find a base to compare — push allowed"; exit 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
for r in "${RANGES[@]}"; do git diff --no-color "$r" -- . "${EXCLUDES[@]}"; done > "$TMP/diff"

LINES=0
for r in "${RANGES[@]}"; do
  n="$(git diff --numstat "$r" -- . "${EXCLUDES[@]}" | awk '$1 != "-" {s += $1 + $2} END {print s + 0}')"
  LINES=$((LINES + n))
done
[[ "$LINES" -eq 0 ]] && { say "no reviewable changes"; exit 0; }
if (( LINES > MAX_LINES )); then
  say "diff has $LINES changed lines (> $MAX_LINES) — too large for the gate, push allowed. Run /dn-review on smaller pieces."
  exit 0
fi

# 2. Run both reviewers in parallel.
REVIEWERS=(dn-code-reviewer dn-security-reviewer)
PROMPT="Review the diff provided on stdin. It is about to be pushed from this repository. Read the surrounding code where needed. Follow your output contract and end with the VERDICT line."
say "reviewing $LINES changed lines with ${REVIEWERS[*]}…"
for a in "${REVIEWERS[@]}"; do
  [[ -f ".claude/agents/$a.md" ]] || { say "$a not installed — skipping it"; continue; }
  ( ${TIMEOUT_CMD[@]+"${TIMEOUT_CMD[@]}"} claude -p --agent "$a" \
      --allowedTools Read Grep Glob --permission-mode dontAsk \
      --output-format text "$PROMPT" < "$TMP/diff" > "$TMP/$a.out" 2> "$TMP/$a.err" ) &
done
wait

# 3. Read the verdicts.
BLOCKED=0
for a in "${REVIEWERS[@]}"; do
  [[ -f "$TMP/$a.out" ]] || continue
  verdict="$(grep -E '^VERDICT: (PASS|BLOCK)' "$TMP/$a.out" | tail -1 | awk '{print $2}')"
  printf '\n----- %s -----\n' "$a" >&2
  if [[ -z "$verdict" ]]; then
    say "$a returned no verdict (error or timeout) — not blocking"
    head -c 600 "$TMP/$a.err" >&2
    continue
  fi
  sed '/^VERDICT:/d' "$TMP/$a.out" >&2
  printf 'VERDICT: %s\n' "$verdict" >&2
  [[ "$verdict" == "BLOCK" ]] && BLOCKED=1
done

if (( BLOCKED )); then
  printf '\n' >&2
  say "push blocked: fix the P1 findings above, or push once with DN_GATE=off git push"
  exit 10
fi
say "PASS"
exit 0
