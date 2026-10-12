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
# Additive and idempotent. Files unchanged since the last install are updated;
# a file you edited is kept unless --force is given, and then it is backed up
# first under .dadosnow/backup/<timestamp>/. .dadosnow/manifest holds the
# hashes that tell the two apart. Run it again any time to update.

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

# .dadosnow/manifest records the hash of every file as the kit installed it,
# so a later install can tell "unchanged since install" (safe to update) from
# "edited by you" (kept unless --force).
MANIFEST="$TARGET/.dadosnow/manifest"
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
installed_hash() { [[ -f "$MANIFEST" ]] && awk -v p="$1" '$2 == p {print $1; exit}' "$MANIFEST" || true; }
NEW_MANIFEST="$(mktemp)"; trap 'rm -f "$NEW_MANIFEST"' EXIT

install_file() {  # $1 = path relative to kit/
  local src="$KIT_DIR/kit/$1" dst="$TARGET/$1" was
  mkdir -p "$(dirname "$dst")"
  was="$(installed_hash "$1")"
  if [[ ! -e "$dst" ]]; then
    cp "$src" "$dst"; added=$((added+1)); echo "  + $1"
  elif cmp -s "$src" "$dst"; then
    :
  elif [[ -n "$was" && "$(sha "$dst")" == "$was" ]]; then
    cp "$src" "$dst"; updated=$((updated+1)); echo "  ~ $1 (updated)"
  elif (( FORCE )); then
    mkdir -p "$BACKUP/$(dirname "$1")"; cp "$dst" "$BACKUP/$1"; cp "$src" "$dst"
    updated=$((updated+1)); echo "  ~ $1 (old copy in .dadosnow/backup/$STAMP/)"
  else
    kept=$((kept+1)); echo "  = $1 (yours differs, kept — use --force to replace)"
  fi
  if cmp -s "$src" "$dst"; then printf '%s  %s\n' "$(sha "$dst")" "$1" >> "$NEW_MANIFEST"
  elif [[ -n "$was" ]]; then printf '%s  %s\n' "$was" "$1" >> "$NEW_MANIFEST"; fi
}

echo "DadosNow kit $KIT_VERSION -> $TARGET"
# A 0.1.0 install has VERSION but no manifest, so every changed kit file looks
# user-edited and would be kept. Say so up front instead of a silent partial upgrade.
LEGACY=0
[[ -f "$TARGET/.dadosnow/VERSION" && ! -f "$MANIFEST" && $FORCE -eq 0 ]] && LEGACY=1
cd "$KIT_DIR/kit"
while IFS= read -r f; do install_file "${f#./}"; done < <(find . -type f ! -path './hooks/*' | sort)
chmod +x "$TARGET/.dadosnow/gate.sh"
# VERSION is stamped only when nothing was left behind.
if (( kept == 0 )); then echo "$KIT_VERSION" > "$TARGET/.dadosnow/VERSION"; fi
cp "$NEW_MANIFEST" "$MANIFEST"

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
if (( LEGACY && kept > 0 )); then
  echo
  echo "  ! No .dadosnow/manifest found: this project was installed by kit 0.1.0, which"
  echo "    did not record hashes, so the installer cannot tell your edits from old kit"
  echo "    files. Run once with --force to update; anything replaced is backed up first"
  echo "    under .dadosnow/backup/. Until then the kept files stay on the old version."
elif (( kept > 0 )); then
  echo "  .dadosnow/VERSION left as is: $kept file(s) kept. Use --force to replace them."
fi
echo
echo "Next:"
echo "  1. Open Claude Code in $TARGET and run /dn-init — it drafts AGENTS.md,"
echo "     CLAUDE.md and .dadosnow/SPEC.md for this repo and asks before writing."
echo "  2. Commit .claude/, .dadosnow/ and the generated files."
echo "  3. Work with /dn-plan, /dn-tdd and /dn-review; the gate runs on git push."
