#!/usr/bin/env bash
# End-to-end tests for install.sh, uninstall.sh and the pre-push gate.
# Uses a stub `claude` so no model is called and nothing is billed.
#   bash tests/test_kit.sh

set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# Stub claude: BLOCK when the diff on stdin contains the marker, PASS otherwise.
# STUB_MODE=crash makes it fail without a verdict.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/claude" <<'EOF'
#!/usr/bin/env bash
[[ "${STUB_MODE:-}" == crash ]] && { echo "boom" >&2; exit 3; }
if grep -q 'SECRET_FOR_TEST' ; then echo "- [P1] secret"; echo "VERDICT: BLOCK"; else echo "(no findings)"; echo "VERDICT: PASS"; fi
EOF
chmod +x "$WORK/bin/claude"
export PATH="$WORK/bin:$PATH"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

new_repo() {  # $1 = name -> repo with a bare remote and one pushed commit
  local r="$WORK/$1"
  git init -q -b main "$r" && git init -q --bare "$r.git"
  echo "print('hi')" > "$r/app.py"
  git -C "$r" add . && git -C "$r" commit -qm init
  git -C "$r" remote add origin "$r.git" && git -C "$r" push -q -u origin main
  echo "$r"
}
commit() { echo "$2" >> "$1/app.py"; git -C "$1" commit -qam "$3"; }
push() { git -C "$1" push -q "${@:2}" >/dev/null 2>&1; }

echo "install"
R="$(new_repo a)"
out="$("$KIT/install.sh" "$R")"
check "files installed" '[[ -f $R/.claude/agents/dn-code-reviewer.md && -x $R/.dadosnow/gate.sh && -f $R/.claude/skills/dn-init/SKILL.md ]]'
check "hook installed" 'grep -q "dadosnow-kit gate" $R/.git/hooks/pre-push && [[ -x $R/.git/hooks/pre-push ]]'
out="$("$KIT/install.sh" "$R")"
check "reinstall is idempotent" 'grep -q "Done: 0 added, 0 replaced, 0 kept" <<<"$out" && [[ $(grep -c ">>> dadosnow-kit gate" $R/.git/hooks/pre-push) -eq 1 ]]'
echo "# mine" >> "$R/.claude/agents/dn-explorer.md"
out="$("$KIT/install.sh" "$R")"
check "edited file kept without --force" 'grep -q "# mine" $R/.claude/agents/dn-explorer.md'
out="$("$KIT/install.sh" "$R" --force)"
check "--force replaces and backs up" '! grep -q "# mine" $R/.claude/agents/dn-explorer.md && grep -rq "# mine" $R/.dadosnow/backup/'
git -C "$R" add -A && git -C "$R" commit -qm kit

echo "gate"
commit "$R" "x = 1" "clean change"
check "clean push passes" 'push "$R"'
commit "$R" "token = 'SECRET_FOR_TEST'" "leak"
err="$(git -C "$R" push 2>&1 >/dev/null)"
check "push with finding is blocked by the gate" '[[ $? -ne 0 ]] && grep -q "push blocked" <<<"$err"'
check "DN_GATE=off skips" 'DN_GATE=off push "$R"'
commit "$R" "y = 2" "another"
mkdir -p "$WORK/minbin"
for t in git bash sh cat sed awk grep head tail mktemp rm mkdir dirname basename tr od wc date cmp find sort env; do
  p="$(command -v "$t")" && ln -sf "$p" "$WORK/minbin/$t"
done
check "no claude on PATH -> allowed" 'PATH="$WORK/minbin" push "$R"'
commit "$R" "z = 3" "crash case"
check "claude crash -> allowed" 'STUB_MODE=crash push "$R"'
git -C "$R" push -q origin main:tmp-branch >/dev/null 2>&1
check "branch deletion -> allowed" 'push "$R" origin :tmp-branch'

echo "existing hook"
H="$(new_repo b)"
printf '#!/usr/bin/env bash\ncat > "%s/refs.txt"\necho mine >> "%s/ran.txt"\n' "$WORK" "$WORK" > "$H/.git/hooks/pre-push"
chmod +x "$H/.git/hooks/pre-push"
"$KIT/install.sh" "$H" >/dev/null
check "block inserted after the shebang" '[[ $(sed -n 2p $H/.git/hooks/pre-push) == "# >>> dadosnow-kit gate >>>" ]]'
git -C "$H" add -A && git -C "$H" commit -qm kit
commit "$H" "a = 1" "change"
push "$H"
check "original hook still runs and gets the ref list" 'grep -q mine $WORK/ran.txt && grep -q refs/heads/main $WORK/refs.txt'

echo "non-shell hook"
P="$(new_repo c)"
printf '#!/usr/bin/env python3\nprint("py hook")\n' > "$P/.git/hooks/pre-push"
before="$(cat "$P/.git/hooks/pre-push")"
out="$("$KIT/install.sh" "$P")"
check "python hook left untouched" '[[ "$(cat $P/.git/hooks/pre-push)" == "$before" ]] && grep -q "NOT installed" <<<"$out"'

echo "core.hooksPath"
K="$(new_repo d)"
git -C "$K" config core.hooksPath .husky
"$KIT/install.sh" "$K" >/dev/null
check "hook goes to core.hooksPath" 'grep -q "dadosnow-kit gate" $K/.husky/pre-push'

echo "uninstall"
"$KIT/install.sh" "$H" >/dev/null
echo "# mine" >> "$H/.claude/skills/dn-plan/SKILL.md"
out="$("$KIT/uninstall.sh" "$H")"
check "unedited kit files removed" '[[ ! -f $H/.claude/agents/dn-code-reviewer.md && ! -f $H/.dadosnow/gate.sh ]]'
check "edited kit file moved to backup" '[[ ! -f $H/.claude/skills/dn-plan/SKILL.md ]] && grep -rq "# mine" $H/.dadosnow/backup/'
check "user hook restored without the block" '! grep -q dadosnow-kit $H/.git/hooks/pre-push && grep -q "echo mine" $H/.git/hooks/pre-push'
"$KIT/uninstall.sh" "$R" >/dev/null
check "gate-only hook removed" '[[ ! -f $R/.git/hooks/pre-push ]]'

echo
echo "$PASS passed, $FAIL failed"
(( FAIL == 0 ))
