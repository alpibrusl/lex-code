# shared_guard.lex — a unit may change its own function, not the file's other ones.
#
# A package is built into ONE source file, src/<project>.lex: every unit's code
# goes into it, and the other units' code is already there. The `write` tool
# replaces a whole file, so a model that writes "its" unit as a new file deletes
# every neighbour's functions, the store then reports them "absent at head", the
# regression pass sends the loop back to rebuild them, and the rebuild clobbers the
# next one. Measured on a real from-scratch build: 53 whole-file writes to the
# shared file across 15 sessions, two simple pure units needing four attempts each
# and 21.7M of the run's 23.1M prompt tokens, with the first unit verified, lost
# and rebuilt.
#
# So before such a write goes through, compare what the file declares now with what
# the new content declares, and refuse a write that drops functions. The refusal
# names them and says what to do instead; `edit` changes one function in place and is
# not affected. Only files a plan scaffolded are guarded: elsewhere, rewriting a
# file whole is an ordinary thing to do.

import "std.str" as str

import "std.list" as list

import "./merge" as merge

# Functions `old_src` declares that `new_src` no longer does, in the old order.
fn dropped_fns(old_src :: Str, new_src :: Str) -> List[Str]
  examples {
    dropped_fns("fn a() -> Int {\n  1\n}\n\nfn b() -> Int {\n  2\n}\n", "fn a() -> Int {\n  1\n}\n") => ["b"],
    dropped_fns("fn a() -> Int {\n  1\n}\n", "fn a() -> Int {\n  1\n}\n\nfn c() -> Int {\n  3\n}\n") => [],
    dropped_fns("fn a() -> Int {\n  1\n}\n\nfn b() -> Int {\n  2\n}\n", "fn b() -> Int {\n  2\n}\n\nfn a() -> Int {\n  1\n}\n") => [],
    dropped_fns("", "fn a() -> Int {\n  1\n}\n") => [],
    dropped_fns("fn a() -> Int {\n  1\n}\n\nfn b() -> Int {\n  2\n}\n", "") => ["a", "b"]
  }
{
  let kept := merge.all_fn_names(new_src)
  list.filter(merge.all_fn_names(old_src), fn (n :: Str) -> Bool {
    not merge.list_has(kept, n)
  })
}

fn refusal(path :: Str, names :: List[Str]) -> Str
  examples {
    refusal("src/p.lex", ["a", "b"]) => "write refused: it would delete code that other units own — a, b. src/p.lex holds every unit's functions, so rewriting it whole drops theirs. Change only your own function with the `edit` tool, or include these functions unchanged in your write."
  }
{
  str.join(["write refused: it would delete code that other units own — ", str.join(names, ", "), ". ", path, " holds every unit's functions, so rewriting it whole drops theirs. Change only your own function with the `edit` tool, or include these functions unchanged in your write."], "")
}

