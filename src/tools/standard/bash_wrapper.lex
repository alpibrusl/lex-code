# The shell script every `bash` tool call runs inside — pure string-building,
# kept apart from the tool itself so it can be tested without importing the
# tool's whole effect row (a module inherits every effect of what it imports).

import "std.str" as str

import "std.int" as int

# Reproduced live: a build agent, mid repair-loop, tried to find a
# validator's exact wording by running `grep -rl "..." ~` — an unbounded
# recursive grep over the whole home directory, no `--exclude-dir`, no
# size cap. `std.process.run` has no timeout of its own (`wait` on a
# `spawn`ed handle is just as blocking), so that one tool call froze the
# entire turn — and the `--auto` run behind it — for hours with nothing
# to show for it, not even partial output: the truncation above only
# bounds a result that comes back at all. This is the other half of that
# fix: a hard wall-clock backstop around every `bash` call, mechanical
# rather than a prompt asking the model to be careful what it greps.
#
# No stdlib primitive does this (`spawn`'s `read_*_line` and `wait` all
# block), and relying on GNU `timeout`/`gtimeout` is not an option — this
# machine has neither installed, so that would leave zero protection on
# the exact host the hang happened on. Implemented in bash itself
# instead. The child's command is passed as a positional parameter
# (`"$1"`), never interpolated into the script text, so nothing about
# the command string can break the wrapper's own quoting no matter what
# the model's command contains.
#
# A first version used `set -m` + `kill -- -$pgid` to reach a stuck
# command's whole descendant tree (e.g. a `grep` a shell spawned), on
# the theory that job control gives a backgrounded job its own process
# group. Reproduced live, the same day, that it doesn't just add
# overhead: under `set -m`, `wait "$child"` on a job that exits near-
# instantly (a plain `echo`) hung indefinitely, every time, with no
# error — some interaction between job-control's own SIGCHLD bookkeeping
# and an explicit-PID `wait` losing the race, not something this fix
# should depend on holding across bash versions. Replaced with
# `pgrep -P` walked recursively from the child's own PID: no job
# control, no process groups, just `wait`/`kill` on plain PIDs, which is
# unglamorous but is the part of bash that has never been in question.
#
# A flag file records whether the watchdog actually fired, so the model
# is told plainly when its own command was killed for taking too long,
# rather than seeing a bare 137. `mktemp` itself *creates* the file (the
# whole point, to hand out a name nothing else raced for) — checking
# `-f` on that path without first `rm`-ing it back out is true from the
# first line, unconditionally; caught by timing the fast path, not by
# reading the script.
#
# The watchdog subshell (`(sleep …; kill_tree …) &`) is explicitly
# redirected to `/dev/null`, not left to inherit this script's own
# stdout/stderr. Reproduced live, in a real `--auto` run: without this,
# EVERY call through this tool — even `pwd`, seconds of real work —
# took the *entire* timeout, every time, because `execute` reads the
# child's output via `std::process::Command::output()`, which blocks
# until it reads true EOF on the pipe. The main script (and the real
# command) can finish and exit in milliseconds, but the watchdog
# subshell, still sleeping in the background, still holds the *same*
# inherited stdout/stderr open — so the pipe's write end stays open,
# and `output()` keeps blocking, until that background sleep finally
# ends on its own. Manual tests that check "is the PID still alive"
# (`kill -0`) never see this, because they don't wait for genuine pipe
# EOF the way `Command::output()` does — confirmed by reproducing both
# the failure and the fix under a harness that actually does
# (`subprocess.run(capture_output=True)`), not by re-running the
# existing tests, which passed throughout.
#
# No `[env]` knob for this: `execute` fills `Tool.execute`'s field,
# whose row `lex-llm/tool` fixes at exactly `[io, net, proc]` — adding
# an effect here to read an override is the library-widening move
# `agent-guidelines` says not to make for one call site. Hardcoded.
fn timeout_secs() -> Int {
  300
}

# A single slow call is unremarkable — a network hiccup, a genuinely
# heavy command. A *cluster* of calls landing near the timeout ceiling
# is the exact pattern that cost 4.5 real hours before anyone noticed
# (`--session-health=` audits this after the fact; this is the same
# check made as each call happens, so it doesn't take a session ending
# before it's visible). 80%, not 100%: the warning should fire before a
# call actually times out, so a truly ordinary-but-heavy command still
# gets its result, with a heads-up alongside it.
fn warn_threshold_secs(timeout :: Int) -> Int {
  timeout * 80 / 100
}

fn watchdog_script(timeout :: Int) -> Str {
  str.join(["start=$(date +%s)\n", "flag=$(mktemp)\n", "rm -f \"$flag\"\n", "out=$(mktemp)\n", "err=$(mktemp)\n", "bash -c \"$1\" </dev/null >\"$out\" 2>\"$err\" &\n", "child=$!\n", "(\n", "  sleep ", int.to_str(timeout), "\n", "  touch \"$flag\"\n", "  kill_tree() {\n", "    local pid=$1\n", "    local c\n", "    for c in $(pgrep -P \"$pid\" 2>/dev/null); do\n", "      kill_tree \"$c\"\n", "    done\n", "    kill -KILL \"$pid\" 2>/dev/null\n", "  }\n", "  kill_tree \"$child\"\n", ") </dev/null >/dev/null 2>&1 &\n", "watchdog=$!\n", "wait \"$child\" 2>/dev/null\n", "status=$?\n", "kill \"$watchdog\" 2>/dev/null\n", "wait \"$watchdog\" 2>/dev/null\n", "orphans=$(lsof -t \"$out\" \"$err\" 2>/dev/null | sort -u | tr '\\n' ' ')\n", "if [ -n \"$orphans\" ]; then\n", "  left=$(( ", int.to_str(timeout), " - ( $(date +%s) - start ) ))\n", "  [ \"$left\" -lt 1 ] && left=1\n", "  ( sleep \"$left\"; kill -KILL $orphans 2>/dev/null ) </dev/null >/dev/null 2>&1 &\n", "fi\n", "cat \"$out\"\n", "cat \"$err\" >&2\n", "rm -f \"$out\" \"$err\"\n", "elapsed=$(( $(date +%s) - start ))\n", "if [ -f \"$flag\" ]; then\n", "  echo \"[lex-code bash tool] command exceeded ", int.to_str(timeout), "s and was killed\" >&2\n", "elif [ \"$elapsed\" -ge ", int.to_str(warn_threshold_secs(timeout)), " ]; then\n", "  echo \"[lex-code bash tool] WARNING: this call took ${elapsed}s (>=", int.to_str(warn_threshold_secs(timeout)), "s, most of the ", int.to_str(timeout), "s timeout) -- if ordinary calls keep landing this high, something is wrong beyond normal latency; check --session-health\" >&2\n", "fi\n", "rm -f \"$flag\"\n", "exit \"$status\"\n"], "")
}

