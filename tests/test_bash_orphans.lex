# Tests for the bash tool's wrapper script (tools/standard/bash.lex).
#
# The case that motivated them: a model debugging a web service starts it with
# `lex run ... main &`, runs `curl`, and ends the command. The command's shell
# exits at once; the server does not, and it still holds the pipe the tool reads
# the command's output from. `std.process.run` reads until that pipe closes, so
# the whole agent turn blocked on a server that never exits — nearly two hours in
# an overnight run, with six tool calls made. The wrapper's own watchdog could
# not help: it kills the command's descendants, and a server whose parent has
# exited is no longer one.
#
# These run the real wrapper with a short timeout, so each case takes seconds.

import "std.int" as int

import "std.io" as io

import "std.list" as list

import "std.process" as proc

import "std.str" as str

import "std.time" as time

import "../src/tools/standard/bash_wrapper" as bash

type Ran = { exit_code :: Int, out :: Str, err :: Str, secs :: Int }

fn check(name :: Str, cond :: Bool) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(name)
  }
}

fn run(cmd :: Str, timeout :: Int) -> [proc, time] Result[Ran, Str] {
  let t0 := time.now()
  match proc.run("bash", ["-c", bash.watchdog_script(timeout), "bash", cmd]) {
    Err(e) => Err(e),
    Ok(o) => Ok({ exit_code: o.exit_code, out: o.stdout, err: o.stderr, secs: time.now() - t0 }),
  }
}

fn alive(marker :: Str) -> [proc] Bool {
  match proc.run("pgrep", ["-f", marker]) {
    Ok(o) => o.exit_code == 0,
    Err(_) => false,
  }
}

fn test_plain_output() -> [proc, time] Result[Unit, Str] {
  match run("echo hello", 5) {
    Err(e) => Err(e),
    Ok(r) => match check("stdout comes back", r.out == "hello\n") {
      Err(e) => Err(e),
      Ok(_) => match check("exit status 0", r.exit_code == 0) {
        Err(e) => Err(e),
        Ok(_) => check("a trivial command does not wait for the timeout", r.secs <= 2),
      },
    },
  }
}

fn test_streams_stay_separate() -> [proc, time] Result[Unit, Str] {
  match run("echo out; echo err >&2", 5) {
    Err(e) => Err(e),
    Ok(r) => match check("stdout is stdout", r.out == "out\n") {
      Err(e) => Err(e),
      Ok(_) => check("stderr is stderr", str.contains(r.err, "err")),
    },
  }
}

fn test_exit_status_is_kept() -> [proc, time] Result[Unit, Str] {
  match run("echo bye; exit 7", 5) {
    Err(e) => Err(e),
    Ok(r) => match check("the command's exit status survives", r.exit_code == 7) {
      Err(e) => Err(e),
      Ok(_) => check("and so does its output", r.out == "bye\n"),
    },
  }
}

fn test_awkward_output_round_trips() -> [proc, time] Result[Unit, Str] {
  match run("printf 'say \"hi\" \\\\ é ✓\\n'", 5) {
    Err(e) => Err(e),
    Ok(r) => check("quotes, a backslash and non-ASCII come back exactly", r.out == "say \"hi\" \\ é ✓\n"),
  }
}

fn test_a_command_cannot_read_the_agents_stdin() -> [proc, time] Result[Unit, Str] {
  match run("cat", 5) {
    Err(e) => Err(e),
    Ok(r) => check("a command that reads stdin gets end-of-file, not a hang", r.secs <= 2 and r.out == ""),
  }
}

# The motivating case. Before the fix this call did not return until the
# background process ended (here: 90 s; in the real run: never).
fn test_a_background_process_does_not_block_the_call() -> [proc, time] Result[Unit, Str] {
  let id := str.join(["3000.", int.to_str(time.now())], "")
  let marker := str.concat("sleep ", id)
  match run(str.join(["sleep ", id, " & echo started"], ""), 6) {
    Err(e) => Err(e),
    Ok(r) => match check("the command's own output is returned", r.out == "started\n") {
      Err(e) => Err(e),
      Ok(_) => match check("the call returns promptly, not when the background process ends", r.secs <= 3) {
        Err(e) => Err(e),
        Ok(_) => {
          let __k := proc.run("pkill", ["-f", marker])
          Ok(())
        },
      },
    },
  }
}

# What the command started may outlive the call, but only until the call's own
# time limit: a debugging session can start a server in one call and use it in the
# next, and nothing leaks for hours.
fn test_a_background_process_is_reaped_at_the_time_limit() -> [proc, time] Result[Unit, Str] {
  let id := str.join(["4000.", int.to_str(time.now())], "")
  let marker := str.concat("sleep ", id)
  match run(str.join(["sleep ", id, " & echo started"], ""), 4) {
    Err(e) => Err(e),
    Ok(_) => match check("it is still running just after the call (usable by the next one)", alive(marker)) {
      Err(e) => {
        let __k := proc.run("pkill", ["-f", marker])
        Err(e)
      },
      Ok(_) => {
        let __w := proc.run("sleep", ["6"])
        let gone := not alive(marker)
        let __k := proc.run("pkill", ["-f", marker])
        check("and gone once the call's time limit has passed", gone)
      },
    },
  }
}

fn test_a_foreground_command_is_killed_at_the_limit() -> [proc, time] Result[Unit, Str] {
  match run("sleep 60; echo never", 3) {
    Err(e) => Err(e),
    Ok(r) => match check("it is killed near the limit, not after 60 s", r.secs >= 3 and r.secs <= 8) {
      Err(e) => Err(e),
      Ok(_) => match check("the model is told its command was killed", str.contains(r.err, "was killed")) {
        Err(e) => Err(e),
        Ok(_) => check("it printed nothing it never got to", r.out == ""),
      },
    },
  }
}

fn suite() -> [proc, time] List[Result[Unit, Str]] {
  [test_plain_output(), test_streams_stay_separate(), test_exit_status_is_kept(), test_awkward_output_round_trips(), test_a_command_cannot_read_the_agents_stdin(), test_a_background_process_does_not_block_the_call(), test_a_background_process_is_reaped_at_the_time_limit(), test_a_foreground_command_is_killed_at_the_limit()]
}

fn run_all() -> [io, proc, time] Unit {
  let results := suite()
  let __dbg := list.map(results, fn (r :: Result[Unit, Str]) -> [io] Unit {
    match r {
      Ok(_) => (),
      Err(e) => io.print(str.concat("FAIL: ", e)),
    }
  })
  let failures := list.fold(results, 0, fn (n :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => n,
      Err(_) => n + 1,
    }
  })
  if failures == 0 {
    ()
  } else {
    let __force_fail := 1 / 0
    ()
  }
}

