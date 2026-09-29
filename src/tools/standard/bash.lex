import "std.process" as proc

import "std.str" as str

import "std.int" as int

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "BashArgs", description: "Run a bash command in the project directory", fields: [s.required_str("command", [])] }
}

# Reproduced live: `grep -R "Unit" ~/.lex/store | head -5` returned 422 MB —
# `head -5` didn't help, because the store's trace files are minified,
# single-line JSON, so five "lines" were five whole files. That result went
# straight into the tool-result JSON handed back to the model; the turn
# after it came back with an empty response, almost certainly from the
# context it blew out. Nothing bounds `bash`'s captured output, and a
# model choosing to grep somewhere broad (a global store, a large log, the
# wrong directory entirely) is a realistic, not adversarial, way to trigger
# this. Each stream is truncated separately, before concatenation, so a
# huge stdout doesn't need to be combined with stderr just to be cut down.
fn max_output_chars() -> Int {
  30000
}

fn truncate_output(s :: Str) -> Str {
  let len := str.len(s)
  if len <= max_output_chars() {
    s
  } else {
    str.join([str.slice(s, 0, max_output_chars()), "\n\n[... output truncated: ", int.to_str(len), " total characters, showing the first ", int.to_str(max_output_chars()), " ...]"], "")
  }
}

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
# No `[env]` knob for this: `execute` fills `Tool.execute`'s field,
# whose row `lex-llm/tool` fixes at exactly `[io, net, proc]` — adding
# an effect here to read an override is the library-widening move
# `agent-guidelines` says not to make for one call site. Hardcoded.
fn timeout_secs() -> Int {
  300
}

fn watchdog_script(timeout :: Int) -> Str {
  str.join(["flag=$(mktemp)\n", "rm -f \"$flag\"\n", "bash -c \"$1\" &\n", "child=$!\n", "(\n", "  sleep ", int.to_str(timeout), "\n", "  touch \"$flag\"\n", "  kill_tree() {\n", "    local pid=$1\n", "    local c\n", "    for c in $(pgrep -P \"$pid\" 2>/dev/null); do\n", "      kill_tree \"$c\"\n", "    done\n", "    kill -KILL \"$pid\" 2>/dev/null\n", "  }\n", "  kill_tree \"$child\"\n", ") &\n", "watchdog=$!\n", "wait \"$child\" 2>/dev/null\n", "status=$?\n", "kill \"$watchdog\" 2>/dev/null\n", "wait \"$watchdog\" 2>/dev/null\n", "if [ -f \"$flag\" ]; then\n", "  echo \"[lex-code bash tool] command exceeded ", int.to_str(timeout), "s and was killed\" >&2\n", "fi\n", "rm -f \"$flag\"\n", "exit \"$status\"\n"], "")
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "command") {
    None => Err(e.single("", "missing_field", "command is required")),
    Some(cmd) => {
      let secs := timeout_secs()
      match proc.run("bash", ["-c", watchdog_script(secs), "bash", cmd]) {
        Err(msg) => Err(e.single("", "proc_error", msg)),
        Ok(out) => {
          let combined := str.concat(truncate_output(out.stdout), truncate_output(out.stderr))
          Ok(JStr(combined))
        },
      }
    },
  }
}

fn tool() -> t.Tool {
  t.define("bash", "Run a bash command and return combined stdout and stderr. Killed if it runs longer than 300s.", params(), execute)
}

