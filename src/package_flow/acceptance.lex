# lex-code — what the finished package must DO, stated before any unit exists
#
# Every unit of a plan verifies on its own, against its own examples. That is
# necessary and not sufficient: on the first from-scratch run that reached the
# end, 20 of 20 units verified and the package still never started — a unit with
# no executable check (`open_db`) failed on every call, `main` was the wrong
# shape for the library it called, and two units that share a data shape (a SQL
# column list and the decoder that reads it) disagreed. None of that is visible
# unit by unit.
#
# So the plan carries a second file, `.lex/plans/<project>.acceptance.json`: a
# handful of black-box scenarios taken from the BRIEF's own requirements — a
# request, and what must come back. After the build, lex-code starts the real
# package on a loopback port with a fresh temp dir, replays the scenarios in
# order against that one server, and reports each. It is the one check in the
# flow that exercises the assembled program rather than a unit.
#
# File shape:
#   { "entry": "main",                      (optional, default "main")
#     "port_env": "INVOICES_PORT",          the env var the server reads its port from
#     "env": { "INVOICES_TOKENS": "tokA:acme,tokB:globex",
#              "INVOICES_DB": "{tmp}/acc.db" },        {port} and {tmp} are expanded
#     "scenarios": [
#       { "name": "no token is rejected", "method": "GET", "path": "/invoices",
#         "headers": { "Authorization": "Bearer x" },   (optional)
#         "body": "{\"a\": 1}", "pad": 5000,            (optional; {pad} in body = pad 'a's)
#         "expect_status": 401,
#         "expect_body_contains": "unauthorized",       (optional)
#         "expect_body_excludes": "tokA" } ] }          (optional)
#
# Everything the planner writes here ends up in an environment and a request, so
# it is checked hard: env names and values and header names and values are
# restricted character sets (no quotes, spaces in names, `;`, `$`, backticks),
# and the runner only ever connects to 127.0.0.1.

import "std.str" as str

import "std.list" as list

import "std.int" as int

import "std.map" as map

import "std.regex" as regex

import "std.bytes" as bytes

import "std.http" as http

import "std.time" as time

import "std.process" as proc

import "std.env" as env

import "lex-schema/json_value" as jv

import "../issue_contract" as ic

type Scenario = { name :: Str, method :: Str, path :: Str, headers :: List[(Str, Str)], body :: Str, pad :: Int, status :: Int, contains :: Str, excludes :: Str }

type Acceptance = { entry :: Str, port_env :: Str, env :: List[(Str, Str)], scenarios :: List[Scenario] }

type AcceptResult = { total :: Int, passed :: Int, failures :: List[Str] }

fn acceptance_path(project :: Str) -> Str {
  str.join([".lex/plans/", project, ".acceptance.json"], "")
}

fn int_field(j :: jv.Json, key :: Str) -> Int {
  match jv.get_field(j, key) {
    Some(JInt(n)) => n,
    _ => 0,
  }
}

fn pairs_field(j :: jv.Json, key :: Str) -> List[(Str, Str)] {
  match jv.get_field(j, key) {
    Some(JObj(fields)) => list.map(fields, fn (p :: (Str, jv.Json)) -> (Str, Str) {
      match p {
        (k, v) => (k, match jv.as_str(v) {
          Some(s) => s,
          None => jv.stringify(v),
        }),
      }
    }),
    _ => [],
  }
}

fn parse_scenario(j :: jv.Json) -> Scenario {
  { name: ic.field_text(j, "name"), method: ic.field_text(j, "method"), path: ic.field_text(j, "path"), headers: pairs_field(j, "headers"), body: ic.field_text(j, "body"), pad: int_field(j, "pad"), status: int_field(j, "expect_status"), contains: ic.field_text(j, "expect_body_contains"), excludes: ic.field_text(j, "expect_body_excludes") }
}

fn parse_acceptance(text :: Str) -> Result[Acceptance, Str]
  examples {
    parse_acceptance("nope") => Err("the acceptance file is not valid JSON"),
    parse_acceptance("{\"port_env\": \"P\", \"scenarios\": []}") => Ok({ entry: "main", port_env: "P", env: [], scenarios: [] }),
    parse_acceptance("{\"entry\": \"serve\", \"port_env\": \"P\", \"env\": {\"A\": \"1\"}, \"scenarios\": [{\"name\": \"n\", \"method\": \"GET\", \"path\": \"/\", \"expect_status\": 200}]}") => Ok({ entry: "serve", port_env: "P", env: [("A", "1")], scenarios: [{ name: "n", method: "GET", path: "/", headers: [], body: "", pad: 0, status: 200, contains: "", excludes: "" }] })
  }
{
  match jv.parse(str.trim(text)) {
    Err(_) => Err("the acceptance file is not valid JSON"),
    Ok(j) => {
      let entry := ic.field_text(j, "entry")
      Ok({ entry: if str.is_empty(entry) {
        "main"
      } else {
        entry
      }, port_env: ic.field_text(j, "port_env"), env: pairs_field(j, "env"), scenarios: list.map(ic.field_list(j, "scenarios"), parse_scenario) })
    },
  }
}

fn problem_if(bad :: Bool, msg :: Str) -> List[Str] {
  if bad {
    [msg]
  } else {
    []
  }
}

fn flat(xs :: List[List[Str]]) -> List[Str] {
  list.fold(xs, [], fn (acc :: List[Str], x :: List[Str]) -> List[Str] {
    list.concat(acc, x)
  })
}

fn env_key_ok(k :: Str) -> Bool
  examples {
    env_key_ok("INVOICES_PORT") => true,
    env_key_ok("port") => false,
    env_key_ok("A B") => false,
    env_key_ok("") => false
  }
{
  regex.is_match_str("^[A-Z][A-Z0-9_]*$", k)
}

fn env_value_ok(v :: Str) -> Bool
  examples {
    env_value_ok("tokA:acme,tokB:globex") => true,
    env_value_ok("{tmp}/acc.db") => true,
    env_value_ok("a b") => false,
    env_value_ok("a;b") => false,
    env_value_ok("$(x)") => false
  }
{
  regex.is_match_str("^[A-Za-z0-9_:.,/@=+{}-]*$", v)
}

fn header_name_ok(k :: Str) -> Bool {
  regex.is_match_str("^[A-Za-z][A-Za-z0-9-]*$", k)
}

fn header_value_ok(v :: Str) -> Bool {
  regex.is_match_str("^[A-Za-z0-9 _:.,/@=+;*-]*$", v)
}

fn path_ok(p :: Str) -> Bool
  examples {
    path_ok("/invoices/1") => true,
    path_ok("/invoices?customer=x%27%20OR") => true,
    path_ok("invoices") => false,
    path_ok("/a b") => false
  }
{
  regex.is_match_str("^/[A-Za-z0-9_./?&=%:+,-]*$", p)
}

fn method_ok(m :: Str) -> Bool {
  m == "GET" or m == "POST" or m == "PUT" or m == "PATCH" or m == "DELETE"
}

fn scenario_errors(s :: Scenario) -> List[Str] {
  let tag := str.join(["scenario `", s.name, "`: "], "")
  let bad_headers := list.filter(s.headers, fn (p :: (Str, Str)) -> Bool {
    match p {
      (k, v) => not header_name_ok(k) or not header_value_ok(v),
    }
  })
  flat([problem_if(str.is_empty(s.name), "a scenario has no name"), problem_if(not method_ok(s.method), str.concat(tag, "method must be GET, POST, PUT, PATCH or DELETE")), problem_if(not path_ok(s.path), str.concat(tag, "path must start with / and use only letters, digits and _ . / ? & = % : + , -")), problem_if(s.status < 100 or s.status > 599, str.concat(tag, "expect_status must be an HTTP status, 100 to 599")), problem_if(not list.is_empty(bad_headers), str.concat(tag, "a header name or value has a character outside letters, digits and - _ : . , / @ = + ; *")), problem_if(s.pad < 0 or s.pad > 100000, str.concat(tag, "pad must be between 0 and 100000")), problem_if(s.pad > 0 and not str.contains(s.body, "{pad}"), str.concat(tag, "pad is set but body has no {pad} to fill"))])
}

fn has_success(scenarios :: List[Scenario]) -> Bool {
  list.fold(scenarios, false, fn (acc :: Bool, s :: Scenario) -> Bool {
    if s.status >= 200 and s.status < 300 {
      true
    } else {
      acc
    }
  })
}

# Pure: what is wrong with this acceptance file, as a list the planner can act on.
fn acceptance_errors(a :: Acceptance) -> List[Str]
  examples {
    acceptance_errors({ entry: "main", port_env: "P", env: [], scenarios: [] }) => ["acceptance needs at least 3 scenarios — cover the brief's requirements, not one happy path", "acceptance needs at least one scenario that expects a 2xx response — otherwise a server that fails every request would pass"]
  }
{
  let env_bad := list.filter(a.env, fn (p :: (Str, Str)) -> Bool {
    match p {
      (k, v) => not env_key_ok(k) or not env_value_ok(v),
    }
  })
  let names := list.map(a.scenarios, fn (s :: Scenario) -> Str {
    s.name
  })
  let dup := list.len(names) != list.len(list.fold(names, [], fn (acc :: List[Str], n :: Str) -> List[Str] {
    if list.fold(acc, false, fn (f :: Bool, x :: Str) -> Bool {
      f or x == n
    }) {
      acc
    } else {
      list.concat(acc, [n])
    }
  }))
  let per := list.fold(a.scenarios, [], fn (acc :: List[Str], s :: Scenario) -> List[Str] {
    list.concat(acc, scenario_errors(s))
  })
  flat([problem_if(not env_key_ok(a.port_env), "port_env must be the NAME of the env var the server reads its port from (upper case, e.g. INVOICES_PORT)"), problem_if(not regex.is_match_str("^[a-z_][a-z0-9_]*$", a.entry), "entry must be the name of the package's entry function (default main)"), problem_if(not list.is_empty(env_bad), "an env name must be UPPER_SNAKE and an env value may only use letters, digits and _ : . , / @ = + - and the {port}/{tmp} placeholders"), problem_if(list.len(a.scenarios) < 3, "acceptance needs at least 3 scenarios — cover the brief's requirements, not one happy path"), problem_if(not has_success(a.scenarios), "acceptance needs at least one scenario that expects a 2xx response — otherwise a server that fails every request would pass"), problem_if(dup, "two scenarios share a name"), per])
}

# Pure + one file read's worth of text in: the problems with the acceptance file's text.
fn check_text(text :: Str) -> List[Str]
  examples {
    check_text("nope") => ["the acceptance file is not valid JSON"]
  }
{
  match parse_acceptance(text) {
    Err(e) => [e],
    Ok(a) => acceptance_errors(a),
  }
}

# ---- running it -------------------------------------------------------------
fn repeat_a(n :: Int) -> Str {
  str.join(list.map(list.range(0, n), fn (_i :: Int) -> Str {
    "a"
  }), "")
}

fn fill(body :: Str, pad :: Int) -> Str
  examples {
    fill("x{pad}y", 3) => "xaaay",
    fill("plain", 0) => "plain",
    fill("{pad}", 0) => ""
  }
{
  str.join(str.split(body, "{pad}"), repeat_a(pad))
}

fn expand(v :: Str, port :: Int, tmp :: Str) -> Str
  examples {
    expand("{tmp}/a.db", 1, "/t") => "/t/a.db",
    expand("p={port}", 7, "/t") => "p=7",
    expand("plain", 7, "/t") => "plain"
  }
{
  str.join(str.split(str.join(str.split(v, "{port}"), int.to_str(port)), "{tmp}"), tmp)
}

fn send(port :: Int, method :: Str, path :: Str, headers :: List[(Str, Str)], body :: Str) -> [net] Result[{ status :: Int, text :: Str }, Str] {
  let base := { method: method, url: str.join(["http://127.0.0.1:", int.to_str(port), path], ""), headers: map.new(), body: if str.is_empty(body) {
    None
  } else {
    Some(bytes.from_str(body))
  }, timeout_ms: Some(5000) }
  let req := list.fold(headers, base, fn (acc :: HttpRequest, p :: (Str, Str)) -> HttpRequest {
    match p {
      (k, v) => http.with_header(acc, k, v),
    }
  })
  match http.send(req) {
    Err(_) => Err("no response"),
    Ok(r) => Ok({ status: r.status, text: match bytes.to_str(r.body) {
      Ok(t) => t,
      Err(_) => "",
    } }),
  }
}

fn listening(port :: Int) -> [net] Bool {
  match send(port, "GET", "/", [], "") {
    Ok(_) => true,
    Err(_) => false,
  }
}

fn pick_port(seed :: Int, tries :: Int) -> [net] Int {
  let p := 21000 + seed % 9000
  if tries > 0 and listening(p) {
    pick_port(seed + 37, tries - 1)
  } else {
    p
  }
}

fn wait_ready(port :: Int, left :: Int) -> [net, time] Bool {
  if listening(port) {
    true
  } else {
    if left <= 0 {
      false
    } else {
      let __s := time.sleep_ms(250)
      wait_ready(port, left - 1)
    }
  }
}

fn scenario_failure(s :: Scenario, got :: { status :: Int, text :: Str }) -> Option[Str] {
  let head := str.join([s.name, ": "], "")
  if got.status != s.status {
    Some(str.join([head, "expected status ", int.to_str(s.status), ", got ", int.to_str(got.status), " — ", str.slice(got.text, 0, 120)], ""))
  } else {
    if not str.is_empty(s.contains) and not str.contains(got.text, s.contains) {
      Some(str.join([head, "response body does not contain `", s.contains, "` — ", str.slice(got.text, 0, 120)], ""))
    } else {
      if not str.is_empty(s.excludes) and str.contains(got.text, s.excludes) {
        Some(str.join([head, "response body must not contain `", s.excludes, "`"], ""))
      } else {
        None
      }
    }
  }
}

fn run_scenario(port :: Int, s :: Scenario) -> [net] Option[Str] {
  match send(port, s.method, s.path, s.headers, fill(s.body, s.pad)) {
    Err(e) => Some(str.join([s.name, ": ", e], "")),
    Ok(got) => scenario_failure(s, got),
  }
}

# One line telling a repairing model exactly how to see a failing scenario for
# itself: the server command with the env the gate uses, and the first failing
# scenario as a curl. Written because a repair run spent its rounds guessing at
# a generic `{"error":"internal server error"}` while a three-call reproduction
# (run the server, send the request, make the handler show its error) names the
# cause. Charsets in a scenario are validated, so nothing here needs shell quoting.
fn repro_line(file :: Str, a :: Acceptance, grants :: Str, failures :: List[Str]) -> Str
  examples {
    repro_line("src/x.lex", { entry: "main", port_env: "P", env: [("DB", "{tmp}/a.db")], scenarios: [{ name: "make", method: "POST", path: "/things", headers: [("Content-Type", "application/json")], body: "{}", pad: 0, status: 201, contains: "", excludes: "" }] }, "net,sql", ["make: expected status 201, got 500 — {}"]) => "to reproduce by hand: start the program with `DB=/tmp/repro/a.db P=7777 lex run --allow-effects net,sql src/x.lex main` in the background, then send the first failing scenario: `curl -s -i -X POST -H 'Content-Type: application/json' --data '{}' http://127.0.0.1:7777/things`. A 500 body is usually generic, so debug in a COPY (`mkdir -p /tmp/repro && cp -R lex.toml src /tmp/repro/`, run it from there) where you make the handler return the underlying error in its body; apply only the real fix to the package, so no debugging output can stay in it.",
    repro_line("src/x.lex", { entry: "main", port_env: "P", env: [], scenarios: [] }, "net", []) => ""
  }
{
  let first := list.fold(a.scenarios, None, fn (found :: Option[Scenario], sc :: Scenario) -> Option[Scenario] {
    match found {
      Some(_) => found,
      None => if list.fold(failures, false, fn (hit :: Bool, f :: Str) -> Bool {
        hit or str.starts_with(f, str.concat(sc.name, ": "))
      }) {
        Some(sc)
      } else {
        None
      },
    }
  })
  match first {
    None => "",
    Some(sc) => {
      let env_words := list.map(list.concat(a.env, [(a.port_env, "{port}")]), fn (kv :: (Str, Str)) -> Str {
        match kv {
          (k, v) => str.join([k, "=", expand(v, 7777, "/tmp/repro")], ""),
        }
      })
      let hdrs := list.map(sc.headers, fn (h :: (Str, Str)) -> Str {
        match h {
          (k, v) => str.join(["-H '", k, ": ", v, "' "], ""),
        }
      })
      let data := if str.is_empty(sc.body) {
        ""
      } else {
        str.join(["--data '", fill(sc.body, sc.pad), "' "], "")
      }
      str.join(["to reproduce by hand: start the program with `", str.join(env_words, " "), " lex run --allow-effects ", grants, " ", file, " ", a.entry, "` in the background, then send the first failing scenario: `curl -s -i -X ", sc.method, " ", str.join(hdrs, ""), data, "http://127.0.0.1:7777", sc.path, "`. A 500 body is usually generic, so debug in a COPY (`mkdir -p /tmp/repro && cp -R lex.toml src /tmp/repro/`, run it from there) where you make the handler return the underlying error in its body; apply only the real fix to the package, so no debugging output can stay in it."], "")
    },
  }
}

fn drain_stderr(h :: ProcessHandle, left :: Int, acc :: List[Str]) -> [proc] List[Str] {
  if left <= 0 {
    acc
  } else {
    match proc.read_stderr_line(h) {
      None => acc,
      Some(l) => drain_stderr(h, left - 1, list.concat(acc, [l])),
    }
  }
}

fn base_env() -> [env] Map[Str, Str] {
  let path := match env.get("PATH") {
    Some(p) => p,
    None => "/usr/bin:/bin",
  }
  let home := match env.get("HOME") {
    Some(h) => h,
    None => "/tmp",
  }
  map.set(map.set(map.new(), "PATH", path), "HOME", home)
}

# Start the package on a loopback port with a fresh temp dir, replay every
# scenario in order against that one server, stop it. Err = the package never
# came up (the strongest result this gate can give: it does not run).
fn run_acceptance(file :: Str, a :: Acceptance, grants :: Str) -> [proc, net, time, env] Result[AcceptResult, Str] {
  match proc.run("mktemp", ["-d"]) {
    Err(e) => Err(str.concat("could not make a temp dir: ", e)),
    Ok(t) => {
      let tmp := str.trim(t.stdout)
      let port := pick_port(time.now(), 8)
      let with_user := list.fold(a.env, base_env(), fn (m :: Map[Str, Str], p :: (Str, Str)) -> Map[Str, Str] {
        match p {
          (k, v) => map.set(m, k, expand(v, port, tmp)),
        }
      })
      let full_env := map.set(with_user, a.port_env, int.to_str(port))
      let started := proc.spawn("lex", ["run", "--max-steps", "20000000000", "--allow-effects", grants, file, a.entry], { cwd: None, env: full_env, stdin: None })
      let outcome := match started {
        Err(e) => Err(str.concat("could not start the package: ", e)),
        Ok(h) => {
          let up := wait_ready(port, 40)
          let result := if up {
            let failures := list.fold(a.scenarios, [], fn (acc :: List[Str], s :: Scenario) -> [net] List[Str] {
              match run_scenario(port, s) {
                None => acc,
                Some(f) => list.concat(acc, [f]),
              }
            })
            Ok({ total: list.len(a.scenarios), passed: list.len(a.scenarios) - list.len(failures), failures: failures })
          } else {
            let __k := proc.kill(h, "TERM")
            let err_lines := drain_stderr(h, 8, [])
            Err(str.join(["the package never accepted a connection on 127.0.0.1:", int.to_str(port), " within 10s", if list.is_empty(err_lines) {
              ""
            } else {
              str.concat(" — it printed: ", str.join(err_lines, " | "))
            }], ""))
          }
          let __k2 := proc.kill(h, "TERM")
          let __w := proc.wait(h)
          result
        },
      }
      let __rm := if str.contains(tmp, "/tmp") and str.len(tmp) > 6 {
        proc.run("rm", ["-rf", tmp])
      } else {
        Ok({ exit_code: 0, stdout: "", stderr: "" })
      }
      outcome
    },
  }
}

