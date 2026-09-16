# find_packages — search existing Lex packages before building your own.
#
# The overlap problem this fixes: an agent with no view of what already
# exists rebuilds it (e.g. reimplementing a crypto library that shipped as
# lex-crypto). This queries the org package catalog — every lex-* package's
# name, description, and exported function signatures — so the model can
# discover and reuse (import a git dep) instead of reinventing.
#
# Backed by a tab-delimited index (catalog.tsv) the hub console serves.
# We never parse the whole catalog in Lex: `grep` prefilters to matching
# lines natively (the full JSON catalog is ~6300 signatures and parsing it
# in the interpreter blows the step limit), and each surviving line is a
# cheap tab split — so a query resolves in well under a second regardless of
# catalog size. Read-only, network-only.

import "std.process" as proc

import "std.str" as str

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

# One row per package. Columns are tab-separated:
#   name \t repo \t description \t "sig | sig | ..."
fn catalog_url() -> Str {
  "https://console.lexlang.org/catalog.tsv"
}

# Where curl drops the index before grep reads it (curl writes the file, so
# no fs_write effect is needed on this tool).
fn catalog_tmp() -> Str {
  "/tmp/lex_find_packages_catalog.tsv"
}

# Cap on how many matched rows we render — a broad token (e.g. a common type
# name) can match most rows; past this we tell the model to narrow instead.
fn max_rows() -> Int {
  20
}

fn params() -> s.ModelSchema {
  { title: "FindPackagesArgs", description: "Search existing Lex packages by name, description, or exported function (e.g. \"gcd\", \"jwt\", \"base32\") before writing your own", fields: [s.required_str("query", [])] }
}

fn col(cols :: List[Str], i :: Int) -> Str {
  if i <= 0 {
    match list.head(cols) {
      Some(v) => v,
      None => "",
    }
  } else {
    col(list.tail(cols), i - 1)
  }
}

# The signatures column, split back into individual signatures.
fn sigs_of(cols :: List[Str]) -> List[Str] {
  list.filter(str.split(col(cols, 3), " | "), fn (sg :: Str) -> Bool {
    not str.is_empty(str.trim(sg))
  })
}

# The function name in a signature: the identifier between "fn " and "(".
# We match on this rather than the whole signature so a query like "rsa"
# surfaces `rsa_encrypt` but not a `run_loop` whose type happens to contain
# "conversation" — grep's substring prefilter is permissive, so this is where
# the noise gets trimmed back out.
fn fn_name(sg :: Str) -> Str {
  let after := match str.strip_prefix(str.trim(sg), "fn ") {
    Some(rest) => rest,
    None => sg,
  }
  match list.head(str.split(after, "(")) {
    Some(n) => str.trim(n),
    None => after,
  }
}

fn sig_name_matches(sg :: Str, q :: Str) -> Bool {
  str.contains(str.to_lower(fn_name(sg)), q)
}

fn matched_sigs(cols :: List[Str], q :: Str) -> List[Str] {
  list.fold(sigs_of(cols), [], fn (acc :: List[Str], sg :: Str) -> List[Str] {
    if sig_name_matches(sg, q) {
      if list.len(acc) < 5 {
        list.concat(acc, [sg])
      } else {
        acc
      }
    } else {
      acc
    }
  })
}

# A grep hit is a real match only if the query is in the package name, its
# description, or an exported function's name — not merely somewhere inside a
# type signature. Keeps the substring prefilter cheap while displayed results
# stay precise.
fn line_matches(line :: Str, q :: Str) -> Bool {
  let cols := str.split(line, "\t")
  if str.contains(str.to_lower(col(cols, 0)), q) {
    true
  } else {
    if str.contains(str.to_lower(col(cols, 2)), q) {
      true
    } else {
      not list.is_empty(matched_sigs(cols, q))
    }
  }
}

fn format_row(line :: Str, q :: Str) -> Str {
  let cols := str.split(line, "\t")
  let name := col(cols, 0)
  let repo := col(cols, 1)
  let desc := col(cols, 2)
  let sigs := matched_sigs(cols, q)
  let sig_line := if list.is_empty(sigs) {
    ""
  } else {
    str.concat("\n    exports: ", str.join(sigs, "  |  "))
  }
  str.join(["• ", name, if str.is_empty(desc) {
    ""
  } else {
    str.concat(" — ", desc)
  }, "\n    depend: ", name, " = { git = \"", repo, "\" }", sig_line], "")
}

fn nonempty(lines :: List[Str], q :: Str) -> List[Str] {
  list.filter(lines, fn (l :: Str) -> Bool {
    if str.is_empty(str.trim(l)) {
      false
    } else {
      line_matches(l, q)
    }
  })
}

fn take(xs :: List[Str], n :: Int) -> List[Str] {
  if n <= 0 {
    []
  } else {
    match list.head(xs) {
      None => [],
      Some(h) => list.concat([h], take(list.tail(xs), n - 1)),
    }
  }
}

fn render(lines :: List[Str], q :: Str, qraw :: Str) -> Str {
  let rows := nonempty(lines, q)
  if list.is_empty(rows) {
    str.join(["No existing Lex package matches \"", qraw, "\". Nothing to reuse — safe to build it."], "")
  } else {
    let total := list.len(rows)
    let shown := take(rows, max_rows())
    let body := str.join(list.map(shown, fn (l :: Str) -> Str {
      format_row(l, q)
    }), "\n")
    let more := if total > max_rows() {
      str.join(["\n… and ", int_str(total - max_rows()), " more — narrow the query to see them."], "")
    } else {
      ""
    }
    str.join([int_str(list.len(shown)), " of ", int_str(total), " existing package(s) match \"", qraw, "\" — reuse before rebuilding:\n", body, more], "")
  }
}

fn int_str(n :: Int) -> Str {
  match n {
    0 => "0",
    _ => nonzero_int_str(n),
  }
}

fn nonzero_int_str(n :: Int) -> Str {
  if n <= 0 {
    ""
  } else {
    str.concat(nonzero_int_str(n / 10), digit(n % 10))
  }
}

fn digit(d :: Int) -> Str {
  match d {
    0 => "0",
    1 => "1",
    2 => "2",
    3 => "3",
    4 => "4",
    5 => "5",
    6 => "6",
    7 => "7",
    8 => "8",
    _ => "9",
  }
}

# grep exits 1 (no error) when nothing matched, and 2 on real trouble. Treat
# an empty stdout as "no matches" regardless of the exit code, so a clean
# "nothing to reuse" never masquerades as a tool failure.
fn grep_lines(out :: { stdout :: Str, stderr :: Str, exit_code :: Int }) -> Result[List[Str], Str] {
  if str.is_empty(str.trim(out.stdout)) {
    if out.exit_code <= 1 {
      Ok([])
    } else {
      Err(util.unavailable("catalog search (grep)", out.stderr))
    }
  } else {
    Ok(str.split(out.stdout, "\n"))
  }
}

fn execute(args :: jv.Json) -> [io, net, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "query") {
    None => Err(e.single("", "missing_field", "query is required")),
    Some(qraw) => {
      let q := str.to_lower(str.trim(qraw))
      if str.len(q) < 2 {
        Err(e.single("", "query_too_short", "query must be at least 2 characters — search for a capability like \"gcd\", \"jwt\", or \"base32\""))
      } else {
        match proc.run("curl", ["-fsSL", "-o", catalog_tmp(), catalog_url()]) {
          Err(msg) => Err(e.single("", "proc_error", msg)),
          Ok(dl) => if not (dl.exit_code == 0) {
            Err(e.single("", "catalog_unavailable", util.unavailable("catalog fetch", util.combined(dl))))
          } else {
            match proc.run("grep", ["-iF", "--", q, catalog_tmp()]) {
              Err(msg) => Err(e.single("", "proc_error", msg)),
              Ok(g) => match grep_lines(g) {
                Err(detail) => Err(e.single("", "catalog_search", detail)),
                Ok(lines) => Ok(JStr(render(lines, q, qraw))),
              },
            }
          },
        }
      }
    },
  }
}

fn tool() -> t.Tool {
  t.define("find_packages", "Search existing Lex packages (name, description, exported functions) before writing new code, so you import and reuse instead of reinventing. Returns matching packages, how to depend on them, and the relevant function signatures.", params(), execute)
}

