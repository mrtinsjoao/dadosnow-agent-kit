#!/usr/bin/env bash
# DadosNow kit — command guard for the two bounded agents.
#
# A Claude Code PreToolUse hook for Bash (install.sh wires it into
# .claude/settings.json). It looks only at commands run by dn-monitor and
# dn-git-ops and denies anything outside the short list each of them is
# allowed. Every other agent, and the main session, pass untouched.
#
# For those two agents it fails closed: a command it cannot read is denied.
# It is a guard against drift, not a sandbox: keep branch protection on your
# Git host.
#
#   dn-monitor   read commands only: gh pr list|view|checks, gh run list|view,
#                git rev-parse, git log -1, date, jq, tail, wc,
#                bash .dadosnow/gate.sh --log. Pipes between them are fine;
#                jq filters must be single-quoted.
#   dn-git-ops   git -C <repo> with: remote, branch --show-current, status,
#                rev-parse, symbolic-ref --short, diff --cached, log,
#                add -- <files>, reset, restore --staged, commit -F -,
#                push <remote> refs/heads/B:refs/heads/B (no flags, never a
#                protected branch); test -f; gh pr create. One command per
#                call; a quoted heredoc is allowed for the message.

set -uo pipefail

IN="$(cat 2>/dev/null || true)"
deny() {  # the reason goes through jq when it can, so quotes in it stay valid JSON
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg r "dn-guard: $1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"dn-guard: command denied"}}\n'
  fi
  exit 0
}
if ! command -v jq >/dev/null 2>&1; then
  grep -qE '"agent_type"[[:space:]]*:[[:space:]]*"([^"]*:)?dn-(monitor|git-ops)"' <<<"$IN" && deny "jq missing"
  exit 0
fi
AGENT="$(jq -r '.agent_type // ""' <<<"$IN" 2>/dev/null)"; AGENT="${AGENT##*:}"
case "$AGENT" in dn-monitor|dn-git-ops) ;; *) exit 0 ;; esac
[[ "$(jq -r '.tool_name // "Bash"' <<<"$IN" 2>/dev/null)" == "Bash" ]] || exit 0
CMD="$(jq -r '.tool_input.command // ""' <<<"$IN" 2>/dev/null)"
[[ -n "$CMD" ]] || deny "empty or unreadable command"

NL=$'\n'
# what is left after removing single-quoted text; that text is never expanded
bare() { printf '%s' "$1" | sed "s/'[^']*'//g"; }
trim() { local v="$1"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; printf '%s' "$v"; }

if [[ "$AGENT" == "dn-monitor" ]]; then
  [[ "$CMD" == *"$NL"* ]] && deny "dn-monitor runs one line at a time"
  B="$(bare "$CMD")"
  [[ "$B" =~ [\;\&\>\<\$\`\"\\] ]] && deny "dn-monitor may not use ; & > < \$ \` \" or a backslash (single-quote jq filters)"
  [[ " $B " == *" --web "* ]] && deny "--web is not a read command"
  IFS='|' read -r -a SEGS <<<"$B"
  for seg in "${SEGS[@]}"; do
    seg="$(trim "$seg")"
    [[ "$seg" =~ ^gh\ pr\ (list|view|checks)(\ |$) ]] && continue
    [[ "$seg" =~ ^gh\ run\ (list|view)(\ |$) ]] && continue
    [[ "$seg" =~ ^git(\ -C\ [^\ ]+)?\ (rev-parse|log\ -1)(\ |$) ]] && continue
    [[ "$seg" =~ ^(date|jq|tail|wc)(\ |$) ]] && continue
    [[ "$seg" == "bash .dadosnow/gate.sh --log" ]] && continue
    deny "not on dn-monitor's list: ${seg:0:60}"
  done
  exit 0
fi

# dn-git-ops: one command, optionally followed by a quoted heredoc body
FIRST="${CMD%%"$NL"*}"
if [[ "$CMD" == *"$NL"* ]]; then
  [[ "$FIRST" =~ \<\<\'EOF\'[[:space:]]*$ ]] || deny "more than one line is allowed only as a <<'EOF' heredoc"
  REST="${CMD#*"$NL"}"
  [[ "${REST##*"$NL"}" == "EOF" ]] || deny "the heredoc must end with EOF as the last line"
  BODY="${REST%EOF}"
  grep -qx 'EOF' <<<"${BODY%"$NL"}" && deny "nothing may follow the heredoc"
  FIRST="${FIRST%%<<*}"
fi
B="$(trim "$(bare "$FIRST")")"
[[ "$B" =~ [\;\&\|\>\<\$\`\"\\] ]] && deny "dn-git-ops may not chain, redirect or expand: one plain command per call"

if [[ "$B" =~ ^git\ -C\ [^\ ]+\ push(\ |$) ]]; then
  [[ "$B" =~ ^git\ -C\ [^\ ]+\ push\ ([A-Za-z0-9._-]+)\ refs/heads/([A-Za-z0-9._/-]+):refs/heads/([A-Za-z0-9._/-]+)$ ]] \
    || deny "the push command is fixed: git -C REPO push REMOTE refs/heads/B:refs/heads/B, no flags"
  [[ "${BASH_REMATCH[2]}" == "${BASH_REMATCH[3]}" ]] || deny "source and destination branch must be the same"
  case "${BASH_REMATCH[2]}" in
    main|master|develop|production|release/*) deny "never push to a protected branch (${BASH_REMATCH[2]})" ;;
  esac
  exit 0
fi
[[ "$B" =~ ^git\ -C\ [^\ ]+\ add\ --\ \.?$ ]] && deny "stage explicit files, never the whole tree"
[[ "$B" =~ ^git\ -C\ [^\ ]+\ (remote|branch\ --show-current|status(\ .*)?|rev-parse\ .+|symbolic-ref\ --short\ [^\ ]+|diff\ --cached(\ --name-only)?|log(\ .*)?|add\ --\ .+|reset(\ -q)?|restore\ --staged\ .+|commit\ -F\ -)$ ]] && exit 0
[[ "$B" =~ ^test\ -f\ [^\ ]+$ ]] && exit 0
if [[ "$B" =~ ^gh\ pr\ create(\ |$) ]]; then
  [[ " $B " == *" --web "* ]] && deny "--web is not allowed"
  exit 0
fi
deny "not on dn-git-ops's list: ${B:0:60}"
