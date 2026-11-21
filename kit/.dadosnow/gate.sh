#!/usr/bin/env bash
# DadosNow kit — pre-push review gate.
#
# Runs dn-code-reviewer and dn-security-reviewer (read-only Claude Code
# subagents) on the commits being pushed. Three things block the push:
#   - a credential pattern in an added line (checked first; nothing is sent
#     to a model in that case);
#   - a reviewer returning "VERDICT: BLOCK";
#   - a reviewer listing a P1 finding, whatever verdict it wrote.
# Everything else is fail-open by default: no Claude Code, an error, a timeout
# or a diff that is too large lets the push through with a warning.
#
#   DN_GATE=off            skip the gate for one push
#   DN_GATE_STRICT=1       fail closed: no Claude Code, a missing reviewer, an
#                          error, a timeout, an answer with no verdict or a
#                          diff over the limit block the push
#   DN_GATE_SECRETS=off    skip the credential scan (false positive)
#   DN_GATE_MAX_LINES=N    skip diffs larger than N changed lines (default 3000)
#   DN_GATE_TIMEOUT=S      seconds per reviewer (default 600)
#
#   gate.sh --log          print the gate log and exit (dn-monitor uses this)
#
# Each run appends one JSON line to <git-common-dir>/dadosnow/gate.jsonl: the
# repository's main .git, shared by every worktree and never committed. A
# write error never blocks.
#
# Called by the pre-push hook with the hook's stdin; also works without it.
# Exit codes: 0 = allow, 10 = blocked by a reviewer. The hook blocks only on
# 10, so a crash or a broken interpreter can never block a push.

set -uo pipefail

say() { printf '[dn-gate] %s\n' "$*" >&2; }

log_dir() {  # the main .git, so worktrees share one log
  local d; d="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  [[ "$d" = /* ]] || d="$(cd "$d" 2>/dev/null && pwd -P)" || return 1
  printf '%s/dadosnow\n' "$d"
}
if [[ "${1:-}" == "--log" ]]; then
  d="$(log_dir)" && [[ -f "$d/gate.jsonl" ]] && cat "$d/gate.jsonl"
  exit 0
fi

[[ "${DN_GATE:-on}" == "off" ]] && { say "skipped (DN_GATE=off)"; exit 0; }
STRICT=0; [[ "${DN_GATE_STRICT:-}" == "1" ]] && STRICT=1

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
START="$(date +%s)"
LINES=0
log_run() {  # $1 = result (allow|block|block-*|skipped-too-large), $2 = verdicts as JSON object
  local dir; dir="$(log_dir)" || return 0
  mkdir -p "$dir" 2>/dev/null || return 0
  { printf '{"ts":"%s","ranges":"%s","lines":%s,"result":"%s","verdicts":%s,"seconds":%s}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${RANGES[*]}" "$LINES" "$1" "$2" "$(( $(date +%s) - START ))" \
      >> "$dir/gate.jsonl"; } 2>/dev/null || true
}
for r in "${RANGES[@]}"; do git diff --no-color "$r" -- . "${EXCLUDES[@]}"; done > "$TMP/diff"

# 2. Credential scan, before anything leaves this machine. Every commit in the
#    push is read, not only the net diff: a key added in one commit and removed
#    in the next still lands in the remote history. Only added lines count, and
#    the value is never printed. (Patterns are spelled sk-an[t]- and PRIVAT[E]
#    so this file does not match itself in a leak scan.)
SECRET_RE='(^|[^A-Za-z0-9])((AKIA|ASIA)[0-9A-Z]{16}|sk-an[t]-[A-Za-z0-9_-]{20,}|sk-(proj|svcacct|admin)-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{32,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{22,}|glpat-[A-Za-z0-9_-]{20,}|xox[abposr]-[A-Za-z0-9-]{10,}|(sk|rk)_live_[A-Za-z0-9]{16,}|AIza[0-9A-Za-z_-]{30,})|-----BEGIN [A-Z ]*PRIVAT[E] KEY-----'
if [[ "${DN_GATE_SECRETS:-on}" != "off" ]]; then
  { cat "$TMP/diff"; for r in "${RANGES[@]}"; do git log -p --no-color --format= "$r" -- . "${EXCLUDES[@]}" 2>/dev/null; done; } \
    | awk '
        /^diff --git / { hdr = 1; next }
        /^@@/ { hdr = 0; n = $0; sub(/^@@ -[0-9,]+ \+/, "", n); sub(/[, ].*/, "", n); line = n - 1; next }
        hdr { if ($0 ~ /^\+\+\+ /) { f = $0; sub(/^\+\+\+ (b\/)?/, "", f) } next }
        /^-/ { next }
        { line++ }
        /^\+/ { print f ":" line "\t" substr($0, 2) }' \
    | { grep -E "$SECRET_RE" || true; } | cut -f1 | sort -u > "$TMP/secrets"
  if [[ -s "$TMP/secrets" ]]; then
    say "credential pattern in added lines — nothing was sent to a reviewer:"
    sed 's/^/[dn-gate]   /' "$TMP/secrets" >&2
    log_run block-secret '{}'
    say "push blocked: remove the credential from the commits (and rotate it). False positive: DN_GATE_SECRETS=off git push"
    exit 10
  fi
fi

if ! command -v claude >/dev/null 2>&1; then
  if (( STRICT )); then log_run block-no-reviewer '{}'; say "push blocked (strict): Claude Code not found, so nothing can review this push"; exit 10; fi
  say "Claude Code not found — push allowed without review"; exit 0
fi

for r in "${RANGES[@]}"; do
  n="$(git diff --numstat "$r" -- . "${EXCLUDES[@]}" | awk '$1 != "-" {s += $1 + $2} END {print s + 0}')"
  LINES=$((LINES + n))
done
[[ "$LINES" -eq 0 ]] && { say "no reviewable changes"; exit 0; }
if (( LINES > MAX_LINES )); then
  if (( STRICT )); then
    say "push blocked (strict): diff has $LINES changed lines (> $MAX_LINES), too large for the gate. Push smaller pieces or raise DN_GATE_MAX_LINES."
    log_run block-too-large '{}'
    exit 10
  fi
  say "diff has $LINES changed lines (> $MAX_LINES) — too large for the gate, push allowed. Run /dn-review on smaller pieces."
  log_run skipped-too-large '{}'
  exit 0
fi

# 3. Run both reviewers in parallel.
REVIEWERS=(dn-code-reviewer dn-security-reviewer); MISSING=0
PROMPT="Review the diff provided on stdin. It is about to be pushed from this repository. Read the surrounding code where needed. Follow your output contract and end with the VERDICT line."
say "reviewing $LINES changed lines with ${REVIEWERS[*]}…"
for a in "${REVIEWERS[@]}"; do
  [[ -f ".claude/agents/$a.md" ]] || { say "$a not installed — skipping it"; MISSING=1; continue; }
  ( ${TIMEOUT_CMD[@]+"${TIMEOUT_CMD[@]}"} claude -p --agent "$a" \
      --allowedTools Read Grep Glob --permission-mode dontAsk \
      --output-format text "$PROMPT" < "$TMP/diff" > "$TMP/$a.out" 2> "$TMP/$a.err" ) &
done
wait

# 4. Read the verdicts. A P1 finding blocks whatever verdict follows it.
BLOCKED=0; UNREVIEWED=$MISSING; VJSON=""
for a in "${REVIEWERS[@]}"; do
  [[ -f "$TMP/$a.out" ]] || continue
  verdict="$(grep -E '^VERDICT: (PASS|BLOCK)' "$TMP/$a.out" | tail -1 | awk '{print $2}')"
  if [[ "$verdict" == "PASS" ]] && grep -qE '^[[:space:]]*-[[:space:]]*\[P1\]' "$TMP/$a.out"; then
    verdict=BLOCK; P1PASS=1
  else P1PASS=0; fi
  VJSON="$VJSON${VJSON:+,}\"$a\":\"${verdict:-none}\""
  printf '\n----- %s -----\n' "$a" >&2
  if [[ -z "$verdict" ]]; then
    UNREVIEWED=1
    if (( STRICT )); then say "$a returned no verdict (error or timeout)"
    else say "$a returned no verdict (error or timeout) — not blocking"; fi
    head -c 600 "$TMP/$a.err" >&2
    continue
  fi
  sed '/^VERDICT:/d' "$TMP/$a.out" >&2
  printf 'VERDICT: %s\n' "$verdict" >&2
  (( P1PASS )) && say "$a wrote PASS but listed a P1 finding — treated as BLOCK"
  [[ "$verdict" == "BLOCK" ]] && BLOCKED=1
done

if (( BLOCKED )); then
  log_run block "{$VJSON}"
  printf '\n' >&2
  say "push blocked: fix the P1 findings above, or push once with DN_GATE=off git push"
  exit 10
fi
if (( STRICT && UNREVIEWED )); then
  log_run block-unreviewed "{$VJSON}"
  printf '\n' >&2
  say "push blocked (strict): a reviewer did not return a verdict. Try again, or push once with DN_GATE=off git push"
  exit 10
fi
log_run allow "{$VJSON}"
say "PASS"
exit 0
