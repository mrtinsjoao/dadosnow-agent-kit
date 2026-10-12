#!/usr/bin/env bash
# DadosNow kit — installer.
#
#   ./install.sh [TARGET_DIR] [--force] [--no-gate]
#
# Copies the kit into TARGET_DIR (default: current directory):
#   .claude/skills/dn-*      skills: dn-init, dn-plan, dn-tdd, dn-review
#   .claude/agents/dn-*      subagents: explorer, two reviewers, git-ops, monitor
#   .dadosnow/               gate script, model reference, templates
#   pre-push hook block      the review gate (skip with --no-gate)
#
# Additive and idempotent: an existing file that differs from the kit is kept
# unless --force is given, and then it is backed up first under
# .dadosnow/backup/<timestamp>/. Run it again any time to update.

set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
KIT_VERSION="$(cat "$KIT_DIR/VERSION")"
TARGET="."; FORCE=0; GATE=1
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --no-gate) GATE=0 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) TARGET="$arg" ;;
  esac
done
TARGET="$(cd "$TARGET" && pwd -P)"
[[ "$TARGET" == "$KIT_DIR" ]] && { echo "Run this from your project, not from the kit itself." >&2; exit 2; }

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$TARGET/.dadosnow/backup/$STAMP"
added=0; updated=0; kept=0

install_file() {  # $1 = path relative to kit/
  local src="$KIT_DIR/kit/$1" dst="$TARGET/$1"
  mkdir -p "$(dirname "$dst")"
  if [[ ! -e "$dst" ]]; then
    cp "$src" "$dst"; added=$((added+1)); echo "  + $1"
  elif cmp -s "$src" "$dst"; then
    :
  elif (( FORCE )); then
    mkdir -p "$BACKUP/$(dirname "$1")"; cp "$dst" "$BACKUP/$1"; cp "$src" "$dst"
    updated=$((updated+1)); echo "  ~ $1 (old copy in .dadosnow/backup/$STAMP/)"
  else
    kept=$((kept+1)); echo "  = $1 (yours differs, kept — use --force to replace)"
  fi
}

echo "DadosNow kit $KIT_VERSION -> $TARGET"
cd "$KIT_DIR/kit"
while IFS= read -r f; do install_file "${f#./}"; done < <(find . -type f ! -path './hooks/*' | sort)
chmod +x "$TARGET/.dadosnow/gate.sh"
echo "$KIT_VERSION" > "$TARGET/.dadosnow/VERSION"

# Backups stay out of git.
GI="$TARGET/.gitignore"
grep -qxF '.dadosnow/backup/' "$GI" 2>/dev/null || { printf '\n# DadosNow kit\n.dadosnow/backup/\n' >> "$GI"; echo "  + .gitignore entry for .dadosnow/backup/"; }

# Review gate on pre-push.
hooks_dir() {  # absolute hooks dir for $1, honoring core.hooksPath (works on git < 2.31)
  local d; d="$(git -C "$1" config --type=path core.hooksPath 2>/dev/null || git -C "$1" config core.hooksPath 2>/dev/null || true)"
  [[ -n "$d" ]] || d="$(git -C "$1" rev-parse --git-path hooks)"
  [[ "$d" = /* ]] || d="$1/$d"
  printf '%s\n' "$d"
}
strip_block() {  # remove our block from $1, only when both markers are present
  grep -q '# >>> dadosnow-kit gate >>>' "$1" && grep -q '# <<< dadosnow-kit gate <<<' "$1" || return 0
  awk '/# >>> dadosnow-kit gate >>>/{skip=1} !skip{print} /# <<< dadosnow-kit gate <<</{skip=0}' "$1" > "$1.dn" && cat "$1.dn" > "$1" && rm -f "$1.dn"
}
if (( GATE )); then
  if git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    HOOKS="$(hooks_dir "$TARGET")"; mkdir -p "$HOOKS"; HOOK="$HOOKS/pre-push"
    [[ "$HOOKS" == "$TARGET"/* ]] || echo "  ! core.hooksPath points outside the project: the gate goes into $HOOKS"
    BLOCK="$KIT_DIR/kit/hooks/pre-push"
    if [[ ! -f "$HOOK" ]]; then
      { echo '#!/bin/sh'; cat "$BLOCK"; } > "$HOOK"; chmod +x "$HOOK"
      echo "  + pre-push gate installed ($HOOK)"
    else
      first="$(head -n 1 "$HOOK")"
      shell_re='(^|[/[:space:]])(sh|bash|dash|zsh|ksh)([[:space:]].*)?$'
      if [[ "$first" == '#!'* && ! "$first" =~ $shell_re ]]; then
        echo "  ! your pre-push hook is not a shell script ($first) — gate NOT installed."
        echo "    Call .dadosnow/gate.sh from it yourself; block the push only when it exits 10."
      else
        if grep -q '# >>> dadosnow-kit gate >>>' "$HOOK" && ! grep -q '# <<< dadosnow-kit gate <<<' "$HOOK"; then
          echo "  ! $HOOK has the gate's start marker but not its end marker — fix or remove that block, then re-run."
          exit 1
        fi
        had=0; grep -q '# >>> dadosnow-kit gate >>>' "$HOOK" && had=1
        strip_block "$HOOK"
        if [[ "$first" == '#!'* ]]; then
          { head -n 1 "$HOOK"; cat "$BLOCK"; tail -n +2 "$HOOK"; } > "$HOOK.dn"
        else
          { cat "$BLOCK"; cat "$HOOK"; } > "$HOOK.dn"
        fi
        cat "$HOOK.dn" > "$HOOK"; rm -f "$HOOK.dn"
        if (( had )); then echo "  = pre-push gate refreshed in $HOOK"
        else echo "  + pre-push gate added at the top of your existing hook ($HOOK)"; fi
        if [[ "$HOOKS" == */.git/hooks && ! -x "$HOOK" ]]; then
          echo "  ! $HOOK is not executable, so git ignores it. Run: chmod +x \"$HOOK\""
        fi
      fi
    fi
  else
    echo "  ! not a git repository — gate not installed (re-run inside a repo)"
  fi
fi

echo
echo "Done: $added added, $updated replaced, $kept kept."
echo
echo "Next:"
echo "  1. Open Claude Code in $TARGET and run /dn-init — it drafts AGENTS.md,"
echo "     CLAUDE.md and .dadosnow/SPEC.md for this repo and asks before writing."
echo "  2. Commit .claude/, .dadosnow/ and the generated files."
echo "  3. Work with /dn-plan, /dn-tdd and /dn-review; the gate runs on git push."
