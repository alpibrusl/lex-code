# lex-code — turning "the assembled program is wrong" into a repair attempt
#
# Units verify one at a time, so a failure that only exists once they are in
# one file (does not type-check; or starts but answers a request wrongly) has
# no unit to blame. Observed live (2026-10-03, invoices): 10 of 10 units
# verified and the assembled file had three errors — `ctx.query_map(ctx)` with a
# parameter named `ctx` shadowing the module alias, handlers registered with a
# library router whose effect row is wider than theirs, and a `main` that
# invoked an effect it never declared. Each sat in a unit that "verified".
#
# So after the build, a failing assembled check — and later a failing acceptance
# scenario — is handed back to a model as ONE integration task: here is what the
# whole program does wrong, and you may edit any function in the file to fix
# it. This module is the pure half: reading the compiler's error list into
# lines a model can act on (which function, which kind, what was expected), the
# prompts, and the short notes about library traps every attempt benefits from.

import "std.str" as str

import "std.list" as list

import "std.int" as int

import "lex-schema/json_value" as jv

import "../issue_contract" as ic

# The name of the `fn` that contains 1-based `line`: the last `fn name(` at or
# above it. "" when there is none (an error above the first function).
fn enclosing_fn(source :: Str, line :: Int) -> Str
  examples {
    enclosing_fn("fn a() -> Int {\n  1\n}\n\nfn b() -> Int {\n  2\n}\n", 2) => "a",
    enclosing_fn("fn a() -> Int {\n  1\n}\n\nfn b() -> Int {\n  2\n}\n", 6) => "b",
    enclosing_fn("fn a() -> Int {\n  1\n}\n\nfn b() -> Int {\n  2\n}\n", 1) => "a",
    enclosing_fn("import \"x\" as x\n\nfn a() -> Int {\n  1\n}\n", 1) => "",
    enclosing_fn("fn a() -> Int {\n  1\n}\n", 99) => "a"
  }
{
  let lines := str.split(source, "\n")
  let found := list.fold(list.enumerate(lines), "", fn (acc :: Str, p :: (Int, Str)) -> Str {
    match p {
      (i, l) => if i + 1 <= line and str.starts_with(l, "fn ") {
        fn_name_of(l)
      } else {
        acc
      },
    }
  })
  found
}

# `fn name(args) -> ...` -> `name`; "" for an anonymous `fn (`.
fn fn_name_of(decl :: Str) -> Str
  examples {
    fn_name_of("fn handler(c :: Ctx) -> Int {") => "handler",
    fn_name_of("fn (x :: Int) -> Int {") => "",
    fn_name_of("fn go[E](x :: Int) -> Int {") => "go"
  }
{
  let rest := str.slice(decl, 3, str.len(decl))
  let cut := list.head(str.split(str.join(str.split(rest, "["), "("), "("))
  match cut {
    Some(n) => str.trim(n),
    None => "",
  }
}

fn int_in(j :: jv.Json, key :: Str) -> Int {
  match jv.get_field(j, key) {
    Some(JInt(n)) => n,
    _ => 0,
  }
}

fn line_of(e :: jv.Json) -> Int {
  match jv.get_field(e, "position") {
    Some(p) => int_in(p, "line"),
    None => 0,
  }
}

fn detail_of(e :: jv.Json) -> Str {
  let parts := list.filter(list.map(["effect", "field", "name", "expected", "got"], fn (k :: Str) -> Str {
    let v := match jv.get_field(e, k) {
      Some(JStr(s)) => s,
      _ => "",
    }
    if str.is_empty(v) {
      ""
    } else {
      str.join([k, " `", v, "`"], "")
    }
  }), fn (s :: Str) -> Bool {
    not str.is_empty(s)
  })
  str.join(parts, ", ")
}

fn describe_one(source :: Str, e :: jv.Json) -> Str {
  let line := line_of(e)
  let where_ := if line > 0 {
    let f := enclosing_fn(source, line)
    if str.is_empty(f) {
      str.join([" at line ", int.to_str(line)], "")
    } else {
      str.join([" at line ", int.to_str(line), " (in `", f, "`)"], "")
    }
  } else {
    ""
  }
  let d := detail_of(e)
  str.join([ic.field_text(e, "kind"), where_, if str.is_empty(d) {
    ""
  } else {
    str.concat(": ", d)
  }], "")
}

# The same description repeated N times (four routes registered the same wrong
# way) becomes one line with "(x4)".
fn dedupe_counts(xs :: List[Str]) -> List[Str]
  examples {
    dedupe_counts([]) => [],
    dedupe_counts(["a", "b", "a", "a"]) => ["a (x3)", "b"],
    dedupe_counts(["a"]) => ["a"]
  }
{
  let uniq := list.fold(xs, [], fn (acc :: List[Str], x :: Str) -> List[Str] {
    if list.fold(acc, false, fn (f :: Bool, y :: Str) -> Bool {
      f or y == x
    }) {
      acc
    } else {
      list.concat(acc, [x])
    }
  })
  list.map(uniq, fn (u :: Str) -> Str {
    let n := list.len(list.filter(xs, fn (x :: Str) -> Bool {
      x == u
    }))
    if n > 1 {
      str.join([u, " (x", int.to_str(n), ")"], "")
    } else {
      u
    }
  })
}

# `lex --output json check FILE`'s stdout -> one line per distinct problem, each
# naming the function it is in. [] when there are no errors. An unreadable
# answer comes back as a single line holding the raw text, never as "no errors".
fn describe_check_errors(source :: Str, stdout :: Str) -> List[Str]
  examples {
    describe_check_errors("fn a() -> Int {\n  1\n}\n", "{\"ok\":true,\"command\":\"check\",\"data\":{\"errors\":[]}}") => [],
    describe_check_errors("fn a() -> Int {\n  1\n}\n", "{\"data\":{\"errors\":[{\"kind\":\"effect_not_declared\",\"effect\":\"approval\",\"position\":{\"line\":2,\"col\":1}}]}}") => ["effect_not_declared at line 2 (in `a`): effect `approval`"],
    describe_check_errors("fn a() -> Int {\n  1\n}\n", "nope") => ["unreadable lex check output: nope"]
  }
{
  match jv.parse(str.trim(stdout)) {
    Err(_) => [str.concat("unreadable lex check output: ", str.slice(str.trim(stdout), 0, 300))],
    Ok(j) => match jv.get_field(j, "data") {
      None => [str.concat("unreadable lex check output: ", str.slice(str.trim(stdout), 0, 300))],
      Some(data) => dedupe_counts(list.map(ic.field_list(data, "errors"), fn (e :: jv.Json) -> Str {
        describe_one(source, e)
      })),
    },
  }
}

# Short notes about traps a model keeps falling into with a known library.
# Selected from lex.toml, shown to every build attempt and every repair. Each one
# was found the hard way on a real run, and costs a unit's whole retry budget
# when a model has to discover it from compiler errors.
fn lexweb_notes() -> Str {
  str.join(["Notes on using lex-web (each of these cost a real run a failed attempt):\n", "- A parameter named like an imported module alias shadows it: with `ctx :: ctx.Ctx`, the call `ctx.query_map(ctx)` is read as a field access on the record. Name parameters differently (`c`, `req`).\n", "- Do NOT write your own router (a function that splits the path and matches method and segments by hand): it is the usual cause of every route but one answering 404. Register routes with `lex-web/router_pure` (`route_named`, then `dispatch_with`), which already handles `:id` path parameters, query strings and method matching.\n", "- `lex-web/router` registers handlers with a fixed, WIDE effect row, so a handler declared `[sql]` is rejected and the wide row leaks into `main` (an undeclared `approval`). For narrow handlers use `lex-web/router_pure`: `route_named(r, \"GET\", \"/things/:id\", \"get_one\")`, then `dispatch_with(r, raw_req, fn (name :: Str, c :: ctx.Ctx) -> [sql] resp.Response { ... })`; path params use `:id`.\n", "- lex-web's `serve[E]` cannot take an effectful handler (lex-web#61). Serve with `net.serve_fn_with(port, handler, { http2: false, inline_vm: false, host: host })`; the handler takes the runtime `Request` and returns the runtime `Response`, so build the lex-web request as `{ body: req.body, method: req.method, path: req.path, query: req.query, headers: req.headers }` and wrap the answer as `{ status: r.status, body: BodyStr(r.body), headers: r.headers }`.\n", "- `main` must declare every effect it reaches and no others (e.g. `[net, sql, env, fs_write]`); opening SQLite declares `fs_write`.\n", "- A whole `main` that passes the checker (imports `lex-web/router_pure as rp`, `std.net as net`, `lex-web/ctx as ctx`, `lex-web/response as resp`): `let r := rp.route_named(rp.route_named(rp.new(), \"GET\", \"/things/:id\", \"get_one\"), \"POST\", \"/things\", \"create\")` then `net.serve_fn_with(port, fn (req :: Request) -> [sql] Response { let raw_req := { body: req.body, method: req.method, path: req.path, query: req.query, headers: req.headers }  let res := rp.dispatch_with(r, raw_req, fn (name :: Str, c :: ctx.Ctx) -> [sql] resp.Response { match name { \"get_one\" => get_one(c, db), \"create\" => create(c, db), _ => resp.not_found() } })  { status: res.status, body: BodyStr(res.body), headers: res.headers } }, { http2: false, inline_vm: false, host: host })`. Declare the closures with the same effect row as your handlers. Never import `lex-web/router` or `lex-web/serve` in `main`.\n", "- One SQL statement per `exec_raw` call: a `;`-separated pair is not run as two, and the second one fails.\n"], "")
}

# The same idea for lex-orm. Found 2026-10-03 on the invoices build: every query
# named its table with `q.with_table(.., "invoices")` except the insert, so the
# insert went to "invoice" (the schema title, lower-cased) and every create
# answered 500 while its unit still verified — a unit's examples never ran SQL.
fn lexorm_notes() -> Str {
  "Notes on using lex-orm (each of these cost a real run a failed attempt):\n- A repo's table name defaults to the schema TITLE lower-cased (`title: \"Invoice\"` -> table `invoice`), not the table you created. Name it explicitly with `q.with_table(repo, \"invoices\")` on EVERY query — select, insert, update and delete — or one of them hits a table that does not exist (\"no such table\").\n- `raw.query_raw(sql, params, db, decoder)` reads ONE column aliased `_j`, and it must be TEXT: a bare INTEGER column (`SELECT last_insert_rowid() AS _j`, `SELECT id AS _j`) aborts the whole call with a runtime error `effect handler error: expected Str, got Int(1)` — a 500 with no decoder error to read. Select a row as `json_object('id', id, 'name', name) AS _j` and a scalar as `CAST(x AS TEXT) AS _j` (the text is parsed as JSON, so `jv.as_int` then works on it). Checked against the library.\n"
}

fn notes_for(lex_toml :: Str) -> Str
  examples {
    notes_for("") => "",
    notes_for("[dependencies]\nlex-schema = { git = \"x\" }\n") => "",
    notes_for("[dependencies]\nlex-orm = { git = \"x\" }\n") => lexorm_notes()
  }
{
  let web := if str.contains(lex_toml, "lex-web") {
    lexweb_notes()
  } else {
    ""
  }
  let orm := if str.contains(lex_toml, "lex-orm") {
    lexorm_notes()
  } else {
    ""
  }
  if str.is_empty(web) {
    orm
  } else {
    if str.is_empty(orm) {
      web
    } else {
      str.join([web, "\n", orm], "")
    }
  }
}

fn bullets(xs :: List[Str]) -> Str {
  str.join(list.map(xs, fn (x :: Str) -> Str {
    str.concat("- ", x)
  }), "\n")
}

fn assembled_prompt(project :: Str, problems :: List[Str], notes :: Str) -> Str {
  str.join(["The package `", project, "` was built unit by unit and every unit passed its own check, but the ASSEMBLED file src/", project, ".lex does not type-check — a problem that only exists once the units are together, so no single unit owns it. You may edit ANY function in src/", project, ".lex to fix it. Keep each unit's public signature and keep its examples passing; change the smallest set of functions that clears the errors.\n\nWhat `lex check` reports, each with the function it is in:\n", bullets(problems), "\n\nRead the file, fix it, run lex_check on src/", project, ".lex until it is clean, then stop. Do not rewrite code that is not implicated.\n", if str.is_empty(notes) {
    ""
  } else {
    str.concat("\n", notes)
  }], "")
}

fn acceptance_prompt(project :: Str, problems :: List[Str], notes :: Str) -> Str {
  str.join(["The package `", project, "` type-checks and every unit verified, but when the real program is started and sent the requests the brief requires, it answers wrongly. These are black-box scenarios from .lex/plans/", project, ".acceptance.json, replayed against the running program, and what went wrong:\n", bullets(problems), "\n\nYou may edit ANY function in src/", project, ".lex. Keep each unit's public signature and keep its examples passing. To see the result for yourself, run `$LEX_CODE_BIN --acceptance-check=", project, "` with bash (it starts the program, replays the scenarios and prints what failed). Fix the cause, not the symptom — a 500 means something raised, find what. Stop when it prints pass.\n", if str.is_empty(notes) {
    ""
  } else {
    str.concat("\n", notes)
  }], "")
}

