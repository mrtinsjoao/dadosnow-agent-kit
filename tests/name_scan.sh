#!/usr/bin/env bash
# Name scan — fails when a term from a private list shows up in a tracked file.
#
# This repository is public. The list of names that must never appear in it
# (clients, companies, people, internal project names) cannot live in it, so
# it is read at run time:
#   DN_DENYLIST        terms separated by newlines or commas (CI: a repository secret)
#   DN_DENYLIST_FILE   one term per line, # comments allowed
#                      (default: ~/.dadosnow/denylist)
# With no list the scan is skipped (exit 0) and says so. Terms match as whole
# words, in any case. A hit prints the file and line, never the term or the
# line's text, so the report is safe in a public CI log.
#
#   bash tests/name_scan.sh        # run from anywhere inside the repository

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "[name-scan] not a git repository" >&2; exit 2; }
cd "$ROOT" || exit 2
FILE="${DN_DENYLIST_FILE:-$HOME/.dadosnow/denylist}"
TERMS="$(mktemp)"; trap 'rm -f "$TERMS"' EXIT
{ printf '%s\n' "${DN_DENYLIST:-}" | tr ',' '\n'
  [[ -f "$FILE" ]] && cat "$FILE"
} | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | sort -u > "$TERMS" || true

N="$(wc -l < "$TERMS" | tr -d ' ')"
if [[ "$N" -eq 0 ]]; then
  echo "[name-scan] skipped: no terms (set DN_DENYLIST or create $FILE)"
  exit 0
fi

HITS="$(git ls-files -z | xargs -0 grep -InwiF -f "$TERMS" -- 2>/dev/null | cut -d: -f1,2 | sort -u || true)"
if [[ -n "$HITS" ]]; then
  echo "[name-scan] a term from the private list appears in tracked files:" >&2
  printf '%s\n' "$HITS" | sed 's/^/[name-scan]   /' >&2
  echo "[name-scan] remove it before pushing (the term itself is not printed here)" >&2
  exit 1
fi
echo "[name-scan] clean: $N terms checked against $(git ls-files | wc -l | tr -d ' ') tracked files"
