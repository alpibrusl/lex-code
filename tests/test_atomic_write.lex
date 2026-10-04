# Tests for tools/atomic.lex: replacing a file so nobody ever reads half of it.
#
# What the properties are for: the shared source file of a package is rewritten by
# every unit's edit, and a run that is killed mid-edit must find the old file or the
# new one, never a truncated mixture. Alongside that, two things a rename would
# silently change must not change: the file's mode and a symbolic link.

import "std.crypto" as crypto

import "std.io" as io

import "std.process" as proc

import "std.list" as list

import "std.str" as str

import "../src/tools/atomic" as at

fn check(name :: Str, cond :: Bool) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(name)
  }
}

fn ok_cmd(cmd :: Str, args :: List[Str]) -> [proc] Bool {
  match proc.run(cmd, args) {
    Ok(o) => o.exit_code == 0,
    Err(_) => false,
  }
}

fn fresh_dir() -> [proc, random, crypto] Str {
  let d := str.join(["/tmp/lexcode-atomic-", crypto.random_str_hex(8)], "")
  let __m := proc.run("mkdir", ["-p", d])
  d
}

fn read_or(path :: Str) -> [io] Str {
  match io.read(path) {
    Ok(t) => t,
    Err(_) => "<unreadable>",
  }
}

fn test_new_file() -> [io, proc, random, crypto] Result[Unit, Str] {
  let d := fresh_dir()
  let p := str.concat(d, "/a.txt")
  match at.write_atomic(p, "hello\n") {
    Err(e) => Err(str.concat("write: ", e)),
    Ok(_) => match check("content is what was written", read_or(p) == "hello\n") {
      Err(e) => Err(e),
      Ok(_) => check("no temporary file is left", not ok_cmd("test", ["-e", at.temp_path(p)])),
    },
  }
}

fn test_replaces_existing_file() -> [io, proc, random, crypto] Result[Unit, Str] {
  let d := fresh_dir()
  let p := str.concat(d, "/a.txt")
  let __w := io.write(p, "old content that is much longer than the new one\n")
  match at.write_atomic(p, "new") {
    Err(e) => Err(str.concat("write: ", e)),
    Ok(_) => match check("the old content is entirely gone (no tail left over)", read_or(p) == "new") {
      Err(e) => Err(e),
      Ok(_) => check("no temporary file is left", not ok_cmd("test", ["-e", at.temp_path(p)])),
    },
  }
}

fn test_keeps_the_mode() -> [io, proc, random, crypto] Result[Unit, Str] {
  let d := fresh_dir()
  let p := str.concat(d, "/run.sh")
  let __w := io.write(p, "#!/bin/sh\necho old\n")
  let __c := proc.run("chmod", ["755", p])
  match check("setup: the file starts executable", ok_cmd("test", ["-x", p])) {
    Err(e) => Err(e),
    Ok(_) => match at.write_atomic(p, "#!/bin/sh\necho new\n") {
      Err(e) => Err(str.concat("write: ", e)),
      Ok(_) => match check("the new content is there", read_or(p) == "#!/bin/sh\necho new\n") {
        Err(e) => Err(e),
        Ok(_) => check("an executable script is still executable after an edit", ok_cmd("test", ["-x", p])),
      },
    },
  }
}

fn test_symlink_is_written_through() -> [io, proc, random, crypto] Result[Unit, Str] {
  let d := fresh_dir()
  let real := str.concat(d, "/real.txt")
  let link := str.concat(d, "/link.txt")
  let __w := io.write(real, "old")
  let __l := proc.run("ln", ["-s", real, link])
  match at.write_atomic(link, "through") {
    Err(e) => Err(str.concat("write: ", e)),
    Ok(_) => match check("the link is still a link", ok_cmd("test", ["-L", link])) {
      Err(e) => Err(e),
      Ok(_) => check("the file it points at changed", read_or(real) == "through"),
    },
  }
}

fn test_a_failure_leaves_nothing() -> [io, proc, random, crypto] Result[Unit, Str] {
  let d := fresh_dir()
  let target := str.concat(d, "/sub")
  let __m := proc.run("mkdir", ["-p", target])
  match at.write_atomic(target, "x") {
    Ok(_) => Err("replacing a directory with a file should have been refused"),
    Err(_) => match check("the directory is untouched", ok_cmd("test", ["-d", target])) {
      Err(e) => Err(e),
      Ok(_) => check("no temporary file is left behind", not ok_cmd("test", ["-e", at.temp_path(target)])),
    },
  }
}

fn test_missing_directory_is_an_error() -> [io, proc, random, crypto] Result[Unit, Str] {
  let d := fresh_dir()
  let p := str.concat(d, "/no/such/dir/a.txt")
  match at.write_atomic(p, "x") {
    Ok(_) => Err("writing into a missing directory should fail, as io.write does"),
    Err(_) => Ok(()),
  }
}

fn test_awkward_content_round_trips() -> [io, proc, random, crypto] Result[Unit, Str] {
  let d := fresh_dir()
  let p := str.concat(d, "/a.txt")
  let tricky := "say \"hi\",\nthen C:\\path\\to\\file\n— ünïcode ✓\n\ttabbed\n"
  match at.write_atomic(p, tricky) {
    Err(e) => Err(str.concat("write: ", e)),
    Ok(_) => check("quotes, backslashes, newlines and non-ASCII come back exactly", read_or(p) == tricky),
  }
}

fn test_many_overwrites_leave_no_stray_file() -> [io, proc, random, crypto] Result[Unit, Str] {
  let d := fresh_dir()
  let p := str.concat(d, "/a.txt")
  let __a := at.write_atomic(p, "1")
  let __b := at.write_atomic(p, "22")
  let __c := at.write_atomic(p, "333")
  let __e := at.write_atomic(p, "4444")
  let last := at.write_atomic(p, "5")
  match last {
    Err(e) => Err(str.concat("write: ", e)),
    Ok(_) => match check("the last write wins", read_or(p) == "5") {
      Err(e) => Err(e),
      Ok(_) => check("only the file itself is in the directory", ok_cmd("test", ["!", "-e", at.temp_path(p)])),
    },
  }
}

fn suite() -> [io, proc, random, crypto] List[Result[Unit, Str]] {
  [test_new_file(), test_replaces_existing_file(), test_keeps_the_mode(), test_symlink_is_written_through(), test_a_failure_leaves_nothing(), test_missing_directory_is_an_error(), test_awkward_content_round_trips(), test_many_overwrites_leave_no_stray_file()]
}

fn run_all() -> [io, proc, random, crypto] Unit {
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

