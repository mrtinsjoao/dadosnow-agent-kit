#!/usr/bin/env bash
# DadosNow kit — uninstaller.
#
#   ./uninstall.sh [TARGET_DIR]
#
# Removes what install.sh added: the dn-* skills and agents, the kit files in
# .dadosnow/ and the gate block in the pre-push hook. Keeps what is yours:
# AGENTS.md, CLAUDE.md, .dadosnow/SPEC.md and any backups.

set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TARGET="$(cd "${1:-.}" && pwd -P)"
echo "Removing the DadosNow kit from $TARGET"

KEEP="$TARGET/.dadosnow/backup/uninstall-$(date +%Y%m%d-%H%M%S)"
MANIFEST="$TARGET/.dadosnow/manifest"
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
installed_hash() { [[ -f "$MANIFEST" ]] && awk -v p="$1" '$2 == p {print $1; exit}' "$MANIFEST" || true; }
cd "$KIT_DIR/kit"
while IFS= read -r f; do
  f="${f#./}"
  [[ -f "$TARGET/$f" ]] || continue
  was="$(installed_hash "$f")"
  if cmp -s "$f" "$TARGET/$f" || [[ -n "$was" && "$(sha "$TARGET/$f")" == "$was" ]]; then rm -f "$TARGET/$f"; echo "  - $f"
  else mkdir -p "$KEEP/$(dirname "$f")"; mv "$TARGET/$f" "$KEEP/$f"; echo "  > $f (you edited it — moved to ${KEEP#$TARGET/}/)"; fi
done < <(find . -type f ! -path './hooks/*' | sort)
rm -f "$TARGET/.dadosnow/VERSION" "$MANIFEST"
for d in "$TARGET"/.claude/skills/dn-* "$TARGET"/.claude/skills "$TARGET"/.claude/agents; do [[ -d "$d" ]] && rmdir "$d" 2>/dev/null || true; done

if git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  HOOKS="$(git -C "$TARGET" config --type=path core.hooksPath 2>/dev/null || git -C "$TARGET" config core.hooksPath 2>/dev/null || true)"
  [[ -n "$HOOKS" ]] || HOOKS="$(git -C "$TARGET" rev-parse --git-path hooks)"
  [[ "$HOOKS" = /* ]] || HOOKS="$TARGET/$HOOKS"
  HOOK="$HOOKS/pre-push"
  if [[ -f "$HOOK" ]] && grep -q '# >>> dadosnow-kit gate >>>' "$HOOK" && grep -q '# <<< dadosnow-kit gate <<<' "$HOOK"; then
    awk '/# >>> dadosnow-kit gate >>>/{skip=1} !skip{print} /# <<< dadosnow-kit gate <<</{skip=0}' "$HOOK" > "$HOOK.dn" && cat "$HOOK.dn" > "$HOOK" && rm -f "$HOOK.dn"
    if ! grep -qvE '^(#!.*)?[[:space:]]*$' "$HOOK"; then rm -f "$HOOK"; echo "  - pre-push hook (was only the gate)"
    else echo "  - gate block removed from $HOOK (your hook kept)"; fi
  elif [[ -f "$HOOK" ]] && grep -q '# >>> dadosnow-kit gate >>>' "$HOOK"; then
    echo "  ! $HOOK has the gate's start marker but not its end marker — remove the block by hand"
  fi
fi

echo
echo "Kept: AGENTS.md, CLAUDE.md, .dadosnow/SPEC.md, .dadosnow/backup/ and any kit file you edited."
echo "Delete them by hand if you no longer want them."
