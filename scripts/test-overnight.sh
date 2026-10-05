#!/usr/bin/env bash
# Tests for bin/lex-code-overnight's decisions, with a stand-in for lex-code that
# plays a scripted sequence of rounds. Nothing here calls a model; it runs in
# well under a minute. `lex` must be on PATH (the supervisor uses `lex check`).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SUP="$HERE/bin/lex-code-overnight"
fails=0
TAB=$'\t'

# A project dir with a plan, a scaffold and a parseable shared file.
mkproj() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/.lex/plans" "$d/src"
  echo '{}' > "$d/.lex/plans/p.json"; echo x > "$d/.lex/plans/p.scaffold"
  printf 'fn f() -> Int {\n  1\n}\n' > "$d/src/p.lex"
  echo "$d"
}

# The stand-in. Each call of `--project=` reads the next line of $SCRIPT_FILE:
#   verdict verified accept [flag]   (flag: corrupt = leave the shared file unparseable)
cat > /tmp/stub-lex-code.$$ <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    --report=*) echo "# stub report"; exit 0 ;;
    --project=*) mode=project ;;
  esac
done
[ "${mode:-}" = project ] || exit 0
n=$(cat "$STUB_STATE" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$STUB_STATE"
echo "$OLLAMA_THINK" >> "$STUB_THINK"
echo "$* | steps=${LEX_MAX_STEPS:-} timeout=${LLM_TIMEOUT_MS:-}" >> "${STUB_ARGS:-/dev/null}"
line=$(sed -n "${n}p" "$SCRIPT_FILE")
read -r verdict verified accept flag <<< "$line"
printf '[PROJECT] p  %s/16 verified, 0 ready\n' "$verified"
[ "$accept" != "-" ] && printf '[ACCEPTANCE] %s/16 scenarios hold:\n' "$accept"
[ "$verdict" = sleep ] && sleep 30
[ "$flag" = corrupt ] && printf 'fn broken( {\n' > src/p.lex
if [ "$flag" = evolve ]; then printf 'fn f() -> Int {\n  2\n}\n' > src/p.lex; sleep 5; printf 'fn broken( {\n' > src/p.lex; sleep 60; fi
[ "$verdict" != none ] && [ "$verdict" != sleep ] && printf '[PROJECT_VERDICT]\t%s\tp\n' "$verdict"
exit 0
EOF
chmod +x /tmp/stub-lex-code.$$
trap 'rm -f /tmp/stub-lex-code.$$' EXIT

# run NAME EXPECTED_EXIT "script lines" [extra supervisor args]  -> sets $D
run() {
  local label="$1" want="$2" script="$3"; shift 3
  D="$(mkproj)"
  printf '%s\n' "$script" > "$D/script"
  ( cd "$D" && STUB_STATE="$D/state" STUB_THINK="$D/think" STUB_ARGS="$D/args" SCRIPT_FILE="$D/script" \
      LEX_CODE_OVERNIGHT_BIN=/tmp/stub-lex-code.$$ LEX_OVERNIGHT_POLL=1 LEX_OVERNIGHT_BACKOFF=1 LEX_OVERNIGHT_MAX_SECS=60 LEX_OVERNIGHT_MIN_LEFT=2 \
      "$SUP" --name=p --no-caffeinate "$@" > "$D/out" 2>&1 )
  local got=$?
  if [ "$got" = "$want" ]; then echo "ok    $label"; else echo "FAIL  $label: exit $got, wanted $want"; sed 's/^/        /' "$D/out" | tail -8; fails=$((fails + 1)); fi
}
expect() {   # expect LABEL FILE PATTERN
  if grep -q -- "$3" "$2" 2>/dev/null; then echo "ok    $1"; else echo "FAIL  $1: '$3' not in $2"; sed 's/^/        /' "$2" 2>/dev/null | tail -6; fails=$((fails + 1)); fi
}

# 1. finishes on the first round
run "done on round 1" 0 "done 16 16"
expect "  report written" "$D/.lex/overnight/REPORT.md" "stub report"

# 2. progress, then done: two rounds, thinking stays off
run "progress then done" 0 $'stuck 5 -\nstuck 9 -\ndone 16 16'
expect "  three rounds ran" "$D/.lex/overnight/rounds.tsv" "^3${TAB}"
if grep -q true "$D/think"; then echo "FAIL  thinking was switched on despite progress"; fails=$((fails + 1)); else echo "ok    thinking stayed off while there was progress"; fi

# 3. no progress: escalate to thinking, then stop after the second stalled round
run "stall escalates then stops" 1 $'stuck 5 -\nstuck 5 -\nstuck 5 -\nstuck 5 -'
expect "  thinking was switched on" "$D/think" "true"
expect "  stopped as stalled" "$D/.lex/overnight/supervisor.log" "stalled"
n=$(wc -l < "$D/think" | tr -d ' ')
if [ "$n" = 3 ]; then echo "ok    stopped after 3 rounds"; else echo "FAIL  ran $n rounds, wanted 3"; fails=$((fails + 1)); fi

# 4. --no-escalate: never thinking, still stops
run "no-escalate" 1 $'stuck 5 -\nstuck 5 -\nstuck 5 -' --no-escalate
if grep -q true "$D/think"; then echo "FAIL  escalated despite --no-escalate"; fails=$((fails + 1)); else echo "ok    no thinking with --no-escalate"; fi

# 5. acceptance count counts as progress (units already all verified)
run "acceptance progress" 0 $'gate_failed 16 10\ngate_failed 16 12\ndone 16 16'
if grep -q true "$D/think"; then echo "FAIL  escalated while acceptance was improving"; fails=$((fails + 1)); else echo "ok    acceptance gains are progress"; fi

# 6. a provider error is waited for, not a failed round
run "provider error then done" 0 $'provider_error 3 -\ndone 16 16'
expect "  it waited" "$D/.lex/overnight/supervisor.log" "provider failed"

# 7. a provider that never comes back ends the run with 4
run "provider stays down" 4 $'provider_error 3 -\nprovider_error 3 -\nprovider_error 3 -\nprovider_error 3 -\nprovider_error 3 -' --outage-minutes=0

# 8. a human-needed verdict stops at once
run "tool bug stops" 1 $'tool_bug_suspected 3 -\ndone 16 16'
n=$(wc -l < "$D/think" | tr -d ' ')
if [ "$n" = 1 ]; then echo "ok    did not retry a tooling bug"; else echo "FAIL  ran $n rounds"; fails=$((fails + 1)); fi

# 9. a kill mid-edit: the unparseable file is put back before the next round
run "restores an unparseable file" 0 $'stuck 5 - corrupt\ndone 16 16'
expect "  restored" "$D/.lex/overnight/supervisor.log" "restored"
if "${LEX:-lex}" check "$D/src/p.lex" >/dev/null 2>&1; then echo "ok    file parses again"; else echo "FAIL  file still broken"; fails=$((fails + 1)); fi

# 9b. the regression that cost a real build 2.5 hours of work: the file evolves during a
# round (valid, newer than the round-start copy), then the round is killed mid-edit. The
# restore must bring back the NEWEST parseable copy, not the round-start one.
D="$(mkproj)"; printf '%s\n' $'none 5 - evolve\ndone 16 16' > "$D/script"
( cd "$D" && STUB_STATE="$D/state" STUB_THINK="$D/think" STUB_ARGS="$D/args" SCRIPT_FILE="$D/script" LEX_CODE_OVERNIGHT_BIN=/tmp/stub-lex-code.$$ \
    LEX_OVERNIGHT_POLL=1 LEX_OVERNIGHT_BACKOFF=1 LEX_OVERNIGHT_ROUND_SECS=9 LEX_OVERNIGHT_SNAPSHOT=1 LEX_OVERNIGHT_MAX_SECS=90 LEX_OVERNIGHT_MIN_LEFT=2 "$SUP" --name=p --no-caffeinate > "$D/out" 2>&1 )
expect "restore happened after the kill" "$D/.lex/overnight/supervisor.log" "restored"
if grep -q "  2" "$D/src/p.lex"; then echo "ok    the restored file is the evolved one, not the round-start copy"; else echo "FAIL  the restore went back to the round-start copy:"; sed 's/^/        /' "$D/src/p.lex"; fails=$((fails + 1)); fi
if ls "$D"/.lex/overnight/broken-*.lex >/dev/null 2>&1; then echo "ok    the broken file was kept"; else echo "FAIL  the broken file was not kept"; fails=$((fails + 1)); fi

# 10. a hung round is killed at its ceiling
D="$(mkproj)"; printf '%s\n' $'sleep 5 -\ndone 16 16' > "$D/script"
( cd "$D" && STUB_STATE="$D/state" STUB_THINK="$D/think" SCRIPT_FILE="$D/script" LEX_CODE_OVERNIGHT_BIN=/tmp/stub-lex-code.$$ \
    LEX_OVERNIGHT_POLL=1 LEX_OVERNIGHT_BACKOFF=1 LEX_OVERNIGHT_ROUND_SECS=3 LEX_OVERNIGHT_MAX_SECS=60 LEX_OVERNIGHT_MIN_LEFT=2 "$SUP" --name=p --no-caffeinate > "$D/out" 2>&1 )
expect "round ceiling kills a hung round" "$D/.lex/overnight/supervisor.log" "ceiling"

# 10b. defaults handed to lex-code: shorter steps, more repair rounds, a long provider timeout
run "defaults reach lex-code" 0 "done 16 16"
expect "  repair rounds default to 6" "$D/args" "repair-rounds=6"
expect "  steps default to 80" "$D/args" "steps=80"
expect "  provider timeout is 15 min" "$D/args" "timeout=900000"
run "an explicit --repair-rounds is respected" 0 "done 16 16" --repair-rounds=2 --steps=40
expect "  the user's repair rounds" "$D/args" "repair-rounds=2"
if grep -q "repair-rounds=6" "$D/args"; then echo "FAIL  the default was added on top of the user's value"; fails=$((fails + 1)); else echo "ok    no second --repair-rounds"; fi
expect "  the user's steps" "$D/args" "steps=40"

# 11. no plan and no brief
D="$(mktemp -d)"
( cd "$D" && LEX_CODE_OVERNIGHT_BIN=/tmp/stub-lex-code.$$ "$SUP" --name=p --no-caffeinate > "$D/out" 2>&1 )
got=$?; if [ "$got" = 3 ]; then echo "ok    no plan, no brief: exit 3"; else echo "FAIL  exit $got, wanted 3"; fails=$((fails + 1)); fi

# 12. usage
( "$SUP" > /dev/null 2>&1 ); got=$?; if [ "$got" = 2 ]; then echo "ok    missing --name: exit 2"; else echo "FAIL  exit $got, wanted 2"; fails=$((fails + 1)); fi

echo
if [ "$fails" = 0 ]; then echo "overnight supervisor: all checks passed"; else echo "overnight supervisor: $fails check(s) FAILED"; exit 1; fi
