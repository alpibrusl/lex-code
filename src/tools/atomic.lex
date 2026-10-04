# atomic.lex — replace a file so that no one ever reads half of it.
#
# `io.write(path, content)` truncates the target and then writes it, so a process
# killed in between leaves a truncated file — and the file the agent edits is the
# one shared source file every unit of a package is built into. An overnight
# run is killed on purpose (a round that hangs is stopped at its ceiling), so
# "killed mid-edit" is a case that happens, not one that is imagined. The shared
# file then fails to parse and the whole build stalls.
#
# The fix is the old one: write the new content beside the target, then rename it
# over the target. A rename within one directory is atomic, so a reader — or the
# next run after a kill — sees the old file or the new one, never a mixture. A
# kill between the two steps leaves a stray `<name>.lexcode-tmp`, which nothing
# reads (its extension is not `.lex`).
#
# Two things a rename would otherwise change, kept as they were:
#   * the file's mode (an edit to an executable script must stay executable): the
#     temporary file starts as a copy of the target, made with `cp -p`, and the
#     new content is written into that copy;
#   * a symbolic link: renaming over it would replace the link with a regular
#     file, so a link is written through, as before.

import "std.io" as io

import "std.str" as str

import "std.process" as proc

fn temp_path(path :: Str) -> Str
  examples {
    temp_path("src/a.lex") => "src/a.lex.lexcode-tmp"
  }
{
  str.concat(path, ".lexcode-tmp")
}

fn succeeded(r :: Result[{ exit_code :: Int, stdout :: Str, stderr :: Str }, Str]) -> Bool {
  match r {
    Ok(o) => o.exit_code == 0,
    Err(_) => false,
  }
}

fn discard(tmp :: Str) -> [proc] Nil {
  let __rm := proc.run("rm", ["-f", tmp])
  ()
}

# Replace `path` with `content`, atomically. Same result type as `io.write`.
fn write_atomic(path :: Str, content :: Str) -> [io, proc] Result[Unit, Str] {
  if succeeded(proc.run("test", ["-L", path])) {
    io.write(path, content)
  } else {
    let tmp := temp_path(path)
    let prepared := if succeeded(proc.run("test", ["-e", path])) {
      if succeeded(proc.run("cp", ["-p", path, tmp])) {
        Ok(())
      } else {
        Err(str.concat("could not prepare a temporary copy of ", path))
      }
    } else {
      Ok(())
    }
    match prepared {
      Err(m) => Err(m),
      Ok(_) => match io.write(tmp, content) {
        Err(m) => {
          let __c := discard(tmp)
          Err(m)
        },
        Ok(_) => match proc.run("mv", ["-f", tmp, path]) {
          Err(m) => {
            let __c := discard(tmp)
            Err(str.concat("could not move the new content into place: ", m))
          },
          Ok(o) => if o.exit_code == 0 {
            Ok(())
          } else {
            let __c := discard(tmp)
            Err(str.concat("could not move the new content into place: ", str.trim(o.stderr)))
          },
        },
      },
    }
  }
}

