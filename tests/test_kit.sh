#!/usr/bin/env bash
# End-to-end tests for install.sh, uninstall.sh and the pre-push gate.
# Uses a stub `claude` so no model is called and nothing is billed.
#   bash tests/test_kit.sh

# check() evals its condition, so variables used only there look unused.
# shellcheck disable=SC2034
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# Stub claude: BLOCK when the diff on stdin contains the marker, PASS otherwise.
# STUB_MODE: crash = fail without a verdict; p1pass = a P1 finding under a PASS
# verdict; noverdict = answer with no verdict line; slow = sleep past a short
# timeout. Each call appends a line to $STUB_CALLS when that is set.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/claude" <<'EOF'
#!/usr/bin/env bash
[[ -n "${STUB_CALLS:-}" ]] && echo call >> "$STUB_CALLS"
case "${STUB_MODE:-}" in
  crash) echo "boom" >&2; exit 3 ;;
  p1pass) cat >/dev/null; echo "- [P1] data loss — app.py:2"; echo "VERDICT: PASS"; exit 0 ;;
  noverdict) cat >/dev/null; echo "I looked at it."; exit 0 ;;
  slow) cat >/dev/null; sleep 5; echo "VERDICT: PASS"; exit 0 ;;
esac
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
check "haiku agents installed" '[[ -f $R/.claude/agents/dn-git-ops.md && -f $R/.claude/agents/dn-monitor.md ]] && grep -q "^model: claude-haiku-5-5" $R/.claude/agents/dn-git-ops.md'
check "agent guard installed and wired once" '[[ -x $R/.dadosnow/agent-guard.sh ]] && [[ $(jq "[.hooks.PreToolUse[] | select(.matcher == \"Bash\")] | length" $R/.claude/settings.json) -eq 1 ]]'
check "dn-lab skill and its results template installed" '[[ -f $R/.claude/skills/dn-lab/SKILL.md && -f $R/.dadosnow/LAB-RESULTS.template.md ]]'
check "dn-lab names the four verdicts and keeps the bench outside the repo" 'grep -q "WORKS WITH CAVEATS" $R/.claude/skills/dn-lab/SKILL.md && grep -q "DOES NOT WORK" $R/.claude/skills/dn-lab/SKILL.md && grep -q "NOT TESTABLE" $R/.claude/skills/dn-lab/SKILL.md && grep -q "outside the repository" $R/.claude/skills/dn-lab/SKILL.md'
check "hook installed" 'grep -q "dadosnow-kit gate" $R/.git/hooks/pre-push && [[ -x $R/.git/hooks/pre-push ]]'
out="$("$KIT/install.sh" "$R")"
check "reinstall is idempotent" 'grep -q "Done: 0 added, 0 replaced, 0 kept" <<<"$out" && [[ $(grep -c ">>> dadosnow-kit gate" $R/.git/hooks/pre-push) -eq 1 ]]'
check "reinstall does not wire the guard twice" '[[ $(grep -c agent-guard.sh $R/.claude/settings.json) -eq 1 ]]'
echo "# mine" >> "$R/.claude/agents/dn-explorer.md"
out="$("$KIT/install.sh" "$R")"
check "edited file kept without --force" 'grep -q "# mine" $R/.claude/agents/dn-explorer.md'
out="$("$KIT/install.sh" "$R" --force)"
check "--force replaces and backs up" '! grep -q "# mine" $R/.claude/agents/dn-explorer.md && grep -rq "# mine" $R/.dadosnow/backup/'
echo "upgrade"
K2="$WORK/kit2"; cp -r "$KIT" "$K2"
echo "# changed in a newer kit" >> "$K2/kit/.dadosnow/models.yaml"
echo "# changed in a newer kit" >> "$K2/kit/.claude/skills/dn-plan/SKILL.md"
echo "# mine" >> "$R/.claude/skills/dn-plan/SKILL.md"
out="$("$K2/install.sh" "$R")"
check "unedited file updated to the newer kit" 'grep -q "changed in a newer kit" $R/.dadosnow/models.yaml && grep -q "models.yaml (updated)" <<<"$out"'
check "edited file still kept on upgrade" 'grep -q "# mine" $R/.claude/skills/dn-plan/SKILL.md && ! grep -q "changed in a newer kit" $R/.claude/skills/dn-plan/SKILL.md'
check "manifest written" '[[ -s $R/.dadosnow/manifest ]] && grep -q " .dadosnow/gate.sh$" $R/.dadosnow/manifest'
echo "upgrade from 0.1.0 (no manifest)"
L="$(new_repo legacy)"
"$KIT/install.sh" "$L" >/dev/null && rm -f "$L/.dadosnow/manifest" && echo "0.1.0" > "$L/.dadosnow/VERSION"
out="$("$K2/install.sh" "$L")"
check "0.1.0: changed kit file kept, with a --force notice" 'grep -q "models.yaml (yours differs" <<<"$out" && grep -q "No .dadosnow/manifest found" <<<"$out" && ! grep -q "changed in a newer kit" $L/.dadosnow/models.yaml'
check "0.1.0: VERSION not stamped while files are kept" 'grep -qx "0.1.0" $L/.dadosnow/VERSION'
out="$("$K2/install.sh" "$L" --force)"
check "0.1.0: --force updates, backs up and writes the manifest" 'grep -q "changed in a newer kit" $L/.dadosnow/models.yaml && ls $L/.dadosnow/backup/*/.dadosnow/models.yaml >/dev/null 2>&1 && [[ -s $L/.dadosnow/manifest ]] && ! grep -qx "0.1.0" $L/.dadosnow/VERSION'
"$KIT/install.sh" "$R" --force >/dev/null
git -C "$R" add -A && git -C "$R" commit -qm kit

echo "gate"
commit "$R" "x = 1" "clean change"
check "clean push passes" 'push "$R"'
GLOG="$R/.git/dadosnow/gate.jsonl"
check "gate run logged as allow" 'tail -1 $GLOG | jq -e ".result == \"allow\" and .verdicts[\"dn-code-reviewer\"] == \"PASS\" and (.lines > 0)" >/dev/null'
commit "$R" "token = 'SECRET_FOR_TEST'" "leak"
err="$(git -C "$R" push 2>&1 >/dev/null)"
check "push with finding is blocked by the gate" '[[ $? -ne 0 ]] && grep -q "push blocked" <<<"$err"'
check "blocked run logged as block" 'tail -1 $GLOG | jq -e ".result == \"block\"" >/dev/null'
check "gate log stays out of the work tree" '[[ -z "$(git -C $R status --porcelain)" ]]'
check "DN_GATE=off skips" 'DN_GATE=off push "$R"'
commit "$R" "w = 4" "big"
check "too-large diff allowed and logged" 'DN_GATE_MAX_LINES=0 push "$R" && tail -1 $GLOG | jq -e ".result == \"skipped-too-large\"" >/dev/null'
echo "v = 5" > "$R/other.py"; git -C "$R" add other.py; git -C "$R" commit -qm "log dir read-only"
chmod 555 "$R/.git/dadosnow"
err="$(git -C "$R" push 2>&1 >/dev/null)"; rc=$?
chmod 755 "$R/.git/dadosnow"
check "log write failure: push allowed, no error printed" '[[ $rc -eq 0 ]] && ! grep -qi "permission denied" <<<"$err"'
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

kit_repo() {  # $1 = name -> repo with the kit installed and committed
  local r; r="$(new_repo "$1")"
  "$KIT/install.sh" "$r" >/dev/null && git -C "$r" add -A && git -C "$r" commit -qm kit && git -C "$r" push -q
  echo "$r"
}
perr() { ERR="$(git -C "$1" push "${@:2}" 2>&1 >/dev/null)"; RC=$?; }   # push, keep stderr and exit code

echo "severity"
S="$(kit_repo sev)"; SLOG="$S/.git/dadosnow/gate.jsonl"
commit "$S" "a = 1" "p1 under pass"
STUB_MODE=p1pass perr "$S"
check "a P1 finding blocks even under VERDICT: PASS" '[[ $RC -ne 0 ]] && grep -q "P1 finding" <<<"$ERR"'
check "that run is logged as block" 'tail -1 $SLOG | jq -e ".result == \"block\"" >/dev/null'

echo "strict mode"
commit "$S" "b = 2" "strict cases"
STUB_MODE=crash perr "$S"; DEFAULT_RC=$RC
git -C "$S" reset -q --hard HEAD~1 >/dev/null; git -C "$S" push -q -f >/dev/null 2>&1; commit "$S" "b = 2" "strict cases"
check "default: a reviewer error still lets the push through" '[[ $DEFAULT_RC -eq 0 ]]'
STUB_MODE=crash DN_GATE_STRICT=1 perr "$S"
check "strict: a reviewer error blocks" '[[ $RC -ne 0 ]] && grep -q "strict" <<<"$ERR"'
STUB_MODE=noverdict DN_GATE_STRICT=1 perr "$S"
check "strict: an answer with no verdict blocks" '[[ $RC -ne 0 ]]'
STUB_MODE=slow DN_GATE_STRICT=1 DN_GATE_TIMEOUT=1 perr "$S"
check "strict: a timeout blocks" '[[ $RC -ne 0 ]]'
DN_GATE_STRICT=1 DN_GATE_MAX_LINES=0 perr "$S"
check "strict: a diff over the limit blocks" '[[ $RC -ne 0 ]] && grep -q "too large" <<<"$ERR"'
check "strict block is logged with its reason" 'tail -1 $SLOG | jq -e ".result == \"block-too-large\"" >/dev/null'
PATH="$WORK/minbin" DN_GATE_STRICT=1 perr "$S"
check "strict: no Claude Code blocks" '[[ $RC -ne 0 ]]'
DN_GATE_STRICT=1 perr "$S"
check "strict: a clean review still passes" '[[ $RC -eq 0 ]]'

echo "secret scan"
FAKE_KEY="AKIA$(printf 'Q%.0s' $(seq 1 16))"          # assembled here so this file holds no match
FAKE_PAT="ghp_$(printf 'a%.0s' $(seq 1 36))"
C="$(kit_repo sec)"; CLOG="$C/.git/dadosnow/gate.jsonl"
commit "$C" "KEY = '$FAKE_KEY'" "leak"
STUB_CALLS="$WORK/calls1" perr "$C"
check "a key in an added line blocks the push" '[[ $RC -ne 0 ]] && grep -q "credential" <<<"$ERR"'
check "no reviewer is called and the diff is not sent" '[[ ! -e "$WORK/calls1" ]]'
check "the file and line are named, the value is not printed" 'grep -q "app.py:" <<<"$ERR" && ! grep -q "$FAKE_KEY" <<<"$ERR"'
check "the run is logged as block-secret" 'tail -1 $CLOG | jq -e ".result == \"block-secret\"" >/dev/null'
check "DN_GATE_SECRETS=off turns the scan off" 'DN_GATE_SECRETS=off push "$C"'
echo "T = '$FAKE_PAT'" > "$C/tmp.py"; git -C "$C" add tmp.py; git -C "$C" commit -qm add
git -C "$C" rm -q tmp.py; git -C "$C" commit -qm remove; commit "$C" "c = 3" "more"
perr "$C"
check "a token added and removed inside the same push is still caught" '[[ $RC -ne 0 ]] && grep -q "tmp.py" <<<"$ERR"'
DN_GATE_SECRETS=off push "$C"
sed -i.bak "/$FAKE_KEY/d" "$C/app.py"; rm -f "$C/app.py.bak"; git -C "$C" commit -qam "remove the key"
STUB_CALLS="$WORK/calls2" perr "$C"
check "removing an old key is not a new leak" '[[ $RC -eq 0 && -s "$WORK/calls2" ]]'
commit "$C" "path = 'disk-$(printf 'a%.0s' $(seq 1 40))'" "long id"
check "a long id after a word ending in sk- is not a key" 'push "$C"'

echo "worktrees"
W="$(kit_repo wt)"; WLOG="$W/.git/dadosnow/gate.jsonl"
git -C "$W" worktree add -q -b feat/wt "$WORK/wt-side" >/dev/null 2>&1
echo "w = 1" >> "$WORK/wt-side/app.py"; git -C "$WORK/wt-side" commit -qam "from worktree"
before="$(wc -l < "$WLOG" 2>/dev/null || echo 0)"
ERR="$(git -C "$WORK/wt-side" push -u origin feat/wt 2>&1 >/dev/null)"; RC=$?
check "a clean push from a worktree is reviewed and passes" '[[ $RC -eq 0 ]] && grep -q "reviewing" <<<"$ERR"'
check "the worktree run lands in the shared gate log" '[[ $(wc -l < "$WLOG") -gt $before ]]'
echo "t = 'SECRET_FOR_TEST'" >> "$WORK/wt-side/app.py"; git -C "$WORK/wt-side" commit -qam "finding"
ERR="$(git -C "$WORK/wt-side" push 2>&1 >/dev/null)"; RC=$?
check "a push with a finding from a worktree is blocked" '[[ $RC -ne 0 ]] && grep -q "push blocked" <<<"$ERR"'
check "gate.sh --log prints the shared log from the worktree" '(cd "$WORK/wt-side" && bash .dadosnow/gate.sh --log | tail -1 | jq -e ".result == \"block\"") >/dev/null'

echo "agent guard"
GUARD="$KIT/kit/.dadosnow/agent-guard.sh"
guard() {  # $1 = agent, $2 = command -> DEC is allow or deny, WHY the reason
  local o; o="$(jq -cn --arg a "$1" --arg c "$2" '{agent_type:$a, tool_name:"Bash", tool_input:{command:$c}}' | bash "$GUARD")"
  if [[ -z "$o" ]]; then DEC=allow; WHY=""; else DEC="$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$o")"; WHY="$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$o")"; fi
}
allows() { guard "$1" "$2"; [[ "$DEC" == allow ]]; }
denies() { guard "$1" "$2"; [[ "$DEC" == deny ]]; }
check "monitor: listing PRs and runs is allowed" 'allows dn-monitor "gh pr list --state open --json number,title" && allows dn-monitor "gh run list --limit 10 --json name,conclusion"'
check "monitor: PR triage and run detail are allowed" 'allows dn-monitor "gh pr view 12 --json additions,deletions,changedFiles,files" && allows dn-monitor "gh pr checks 12" && allows dn-monitor "gh run view 99 --json conclusion,jobs"'
check "monitor: the gate log piped through jq and tail is allowed" "allows dn-monitor \"bash .dadosnow/gate.sh --log | jq -c 'select(.result != \\\"allow\\\")' | tail -5\""
check "monitor: merge, comment, rerun and api are denied" 'denies dn-monitor "gh pr merge 12" && denies dn-monitor "gh pr comment 12 -b hi" && denies dn-monitor "gh run rerun 99" && denies dn-monitor "gh api repos/x/y"'
check "monitor: a second command after ; or && is denied" 'denies dn-monitor "gh run list; rm -rf x" && denies dn-monitor "gh run list && git push"'
check "monitor: command substitution and redirection are denied" 'denies dn-monitor "tail -1 \$(cat x)" && denies dn-monitor "gh pr list > out.txt"'
check "monitor: a forbidden command hidden after a pipe is denied" 'denies dn-monitor "gh pr list | sh"'
check "a denial is valid JSON with a reason" '[[ "$WHY" == dn-guard:* ]]'
check "git-ops: the fixed push form on a feature branch is allowed" 'allows dn-git-ops "git -C /r push origin refs/heads/feat/x:refs/heads/feat/x"'
check "git-ops: force, other flags and a different destination are denied" 'denies dn-git-ops "git -C /r push --force origin refs/heads/feat/x:refs/heads/feat/x" && denies dn-git-ops "git -C /r push origin refs/heads/feat/x:refs/heads/other" && denies dn-git-ops "git -C /r push origin feat/x"'
check "git-ops: protected branches are denied" 'denies dn-git-ops "git -C /r push origin refs/heads/main:refs/heads/main" && denies dn-git-ops "git -C /r push origin refs/heads/release/1:refs/heads/release/1"'
check "git-ops: turning the gate off or skipping hooks is denied" 'denies dn-git-ops "DN_GATE=off git -C /r push origin refs/heads/a:refs/heads/a" && denies dn-git-ops "git -C /r -c core.hooksPath=/dev/null push origin refs/heads/a:refs/heads/a"'
check "git-ops: staging explicit files is allowed, the whole tree is not" 'allows dn-git-ops "git -C /r add -- src/a.py b.txt" && denies dn-git-ops "git -C /r add -A" && denies dn-git-ops "git -C /r add -- ."'
check "git-ops: a commit message heredoc is allowed, whatever it contains" 'allows dn-git-ops "$(printf "git -C /r commit -F - <<'"'"'EOF'"'"'\nfix; \$(x) and \`y\`\nEOF")"'
check "git-ops: a command after the heredoc is denied" 'denies dn-git-ops "$(printf "git -C /r commit -F - <<'"'"'EOF'"'"'\nmsg\nEOF\nrm -rf /")"'
check "git-ops: merge and rebase are denied" 'denies dn-git-ops "git -C /r merge main" && denies dn-git-ops "git -C /r rebase main" && denies dn-git-ops "gh pr merge 3"'
check "other agents and the main session are never touched" 'allows dn-explorer "rm -rf x | sh" && allows "" "git push --force"'

echo "guard wiring keeps existing settings"
G="$(new_repo g)"; mkdir -p "$G/.claude"
echo '{"permissions":{"allow":["Bash(ls:*)"]},"hooks":{"PreToolUse":[{"matcher":"Write","hooks":[{"type":"command","command":"echo mine"}]}]}}' > "$G/.claude/settings.json"
"$KIT/install.sh" "$G" >/dev/null
check "the user's own settings and hooks survive the install" 'jq -e ".permissions.allow[0] == \"Bash(ls:*)\" and (.hooks.PreToolUse | length) == 2 and .hooks.PreToolUse[0].hooks[0].command == \"echo mine\"" $G/.claude/settings.json >/dev/null'
"$KIT/uninstall.sh" "$G" >/dev/null
check "uninstall removes only the guard entry" 'jq -e ".permissions.allow[0] == \"Bash(ls:*)\" and (.hooks.PreToolUse | length) == 1" $G/.claude/settings.json >/dev/null && ! grep -q agent-guard $G/.claude/settings.json'
B2="$(new_repo g2)"; mkdir -p "$B2/.claude"; echo 'not json' > "$B2/.claude/settings.json"
out="$("$KIT/install.sh" "$B2")"
check "invalid settings.json is left alone, with a warning" 'grep -q "not valid JSON" <<<"$out" && [[ "$(cat $B2/.claude/settings.json)" == "not json" ]]'

echo "name scan"
SCAN="$KIT/tests/name_scan.sh"
N="$(new_repo names)"; echo "we built this for Zorblat Widgets last year" > "$N/notes.md"; echo "zorblatish is another word" > "$N/other.md"
git -C "$N" add -A; git -C "$N" commit -qm notes
out="$(cd "$N" && DN_DENYLIST="Zorblat Widgets" bash "$SCAN" 2>&1)"; rc=$?
check "a denied name in a tracked file fails the scan" '[[ $rc -ne 0 ]] && grep -q "notes.md:1" <<<"$out"'
check "the report names file and line but never the term" '! grep -qi "zorblat" <<<"$out"'
out="$(cd "$N" && DN_DENYLIST="zorblat" bash "$SCAN" 2>&1)"; rc=$?
check "terms match whole words, any case" '[[ $rc -ne 0 ]] && grep -q "notes.md" <<<"$out" && ! grep -q "other.md" <<<"$out"'
printf 'Quuxterm\n# a comment\n\nFnordly\n' > "$WORK/deny.txt"
out="$(cd "$N" && DN_DENYLIST_FILE="$WORK/deny.txt" bash "$SCAN" 2>&1)"; rc=$?
check "a clean tree passes, and says how many terms were checked" '[[ $rc -eq 0 ]] && grep -q "2 terms" <<<"$out"'
out="$(cd "$N" && DN_DENYLIST="" DN_DENYLIST_FILE="$WORK/none.txt" bash "$SCAN" 2>&1)"; rc=$?
check "no list: the scan is skipped and says so" '[[ $rc -eq 0 ]] && grep -q "skipped" <<<"$out"'
echo "Zorblat Widgets again" > "$N/untracked.md"
out="$(cd "$N" && DN_DENYLIST="Fnordly" bash "$SCAN" 2>&1)"; rc=$?
check "untracked files are not scanned" '[[ $rc -eq 0 ]]'

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
check "unedited kit files removed" '[[ ! -f $H/.claude/agents/dn-code-reviewer.md && ! -f $H/.claude/agents/dn-git-ops.md && ! -f $H/.claude/agents/dn-monitor.md && ! -f $H/.dadosnow/gate.sh ]]'
check "edited kit file moved to backup" '[[ ! -f $H/.claude/skills/dn-plan/SKILL.md ]] && grep -rq "# mine" $H/.dadosnow/backup/'
check "user hook restored without the block" '! grep -q dadosnow-kit $H/.git/hooks/pre-push && grep -q "echo mine" $H/.git/hooks/pre-push'
"$KIT/uninstall.sh" "$R" >/dev/null
check "gate-only hook removed" '[[ ! -f $R/.git/hooks/pre-push ]]'
check "settings.json that held only the guard is removed" '[[ ! -f $R/.claude/settings.json ]]'

echo
echo "$PASS passed, $FAIL failed"
(( FAIL == 0 ))
