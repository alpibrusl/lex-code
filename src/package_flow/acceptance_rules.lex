# lex-code — coverage rules for an acceptance file (pure)
#
# The acceptance scenarios are the only thing in a package build that runs the
# assembled program, so what they leave unasked, nothing asks. Two real builds
# showed the gaps:
#
#   * a jobs API passed 18 of 18 scenarios and still answered 500 to a plain
#     `GET /jobs`: its only listing scenario carried `?state=done`, and the
#     branch for "no filter" was never run;
#   * an invoices API let one tenant "pay" another tenant's invoice (200 for an
#     id it does not own), because no scenario asked.
#
# So an acceptance file is rejected, at plan time, when it leaves either case
# unasked. These rules see only a `Probe` (method, path, status, the
# Authorization header value) so they stay pure, with no import of the runner,
# and `lex test` can exercise them without network or environment grants.

import "std.str" as str

import "std.list" as list

import "std.regex" as regex

type Probe = { method :: Str, path :: Str, status :: Int, auth :: Str }

fn is_2xx(s :: Probe) -> Bool {
  s.status >= 200 and s.status < 300
}

fn base_path(p :: Str) -> Str
  examples {
    base_path("/jobs?state=done") => "/jobs",
    base_path("/jobs/1") => "/jobs/1",
    base_path("/jobs?") => "/jobs"
  }
{
  match list.head(str.split(p, "?")) {
    Some(h) => h,
    None => p,
  }
}

fn has_query(p :: Str) -> Bool
  examples {
    has_query("/jobs?limit=5") => true,
    has_query("/jobs") => false,
    has_query("/jobs/1") => false
  }
{
  str.contains(p, "?")
}

# A path with a numeric segment (`/jobs/1`, `/jobs/1/claim`) names one resource.
fn has_id_segment(p :: Str) -> Bool
  examples {
    has_id_segment("/jobs/1") => true,
    has_id_segment("/jobs/12/claim") => true,
    has_id_segment("/jobs") => false,
    has_id_segment("/jobs/abc") => false
  }
{
  regex.is_match_str("^(/[^/?]+)*/[0-9]+(/[^/?]*)*$", base_path(p))
}

fn dedup_strs(xs :: List[Str]) -> List[Str]
  examples {
    dedup_strs(["a", "b", "a"]) => ["a", "b"],
    dedup_strs([]) => []
  }
{
  list.fold(xs, [], fn (acc :: List[Str], x :: Str) -> List[Str] {
    if list.fold(acc, false, fn (f :: Bool, y :: Str) -> Bool {
      f or y == x
    }) {
      acc
    } else {
      list.concat(acc, [x])
    }
  })
}

# A route that is only ever exercised WITH a query string has never been called
# the way a client most often calls it.
fn bare_route_errors(scenarios :: List[Probe]) -> List[Str]
  examples {
    bare_route_errors([{ method: "GET", path: "/x?a=1", status: 200, auth: "" }]) => ["GET /x is only exercised with a query string — add a scenario that calls it with NO query parameters and expects a 2xx (the no-filter, all-defaults case is the one most clients send)"],
    bare_route_errors([{ method: "GET", path: "/x?a=1", status: 200, auth: "" }, { method: "GET", path: "/x", status: 200, auth: "" }]) => []
  }
{
  dedup_strs(list.fold(scenarios, [], fn (acc :: List[Str], s :: Probe) -> List[Str] {
    if is_2xx(s) and has_query(s.path) {
      let covered := list.fold(scenarios, false, fn (f :: Bool, t :: Probe) -> Bool {
        f or is_2xx(t) and t.method == s.method and base_path(t.path) == base_path(s.path) and not has_query(t.path)
      })
      if covered {
        acc
      } else {
        list.concat(acc, [str.join([s.method, " ", base_path(s.path), " is only exercised with a query string — add a scenario that calls it with NO query parameters and expects a 2xx (the no-filter, all-defaults case is the one most clients send)"], "")])
      }
    } else {
      acc
    }
  }))
}

fn distinct_auths(scenarios :: List[Probe]) -> Int {
  list.len(dedup_strs(list.filter(list.map(scenarios, fn (s :: Probe) -> Str {
    s.auth
  }), fn (a :: Str) -> Bool {
    not str.is_empty(a)
  })))
}

# With more than one tenant in play, every scenario that SUCCEEDS on one
# tenant's resource needs a twin: the same method and path from a different
# tenant's token that must come back 404. Without it a handler that forgets the
# ownership check passes every scenario.
fn twin_errors(scenarios :: List[Probe]) -> List[Str]
  examples {
    twin_errors([{ method: "POST", path: "/x/1/go", status: 200, auth: "Bearer A" }]) => [],
    twin_errors([{ method: "POST", path: "/x/1/go", status: 200, auth: "Bearer A" }, { method: "GET", path: "/x", status: 200, auth: "Bearer B" }]) => ["POST /x/1/go succeeds for one tenant but has no cross-tenant twin — add a scenario with the same method and path, a DIFFERENT tenant's Authorization header, expecting 404 (never 403: existence must not leak)"]
  }
{
  if distinct_auths(scenarios) < 2 {
    []
  } else {
    dedup_strs(list.fold(scenarios, [], fn (acc :: List[Str], s :: Probe) -> List[Str] {
      if is_2xx(s) and has_id_segment(s.path) and not str.is_empty(s.auth) {
        let twinned := list.fold(scenarios, false, fn (f :: Bool, t :: Probe) -> Bool {
          f or t.status == 404 and t.method == s.method and base_path(t.path) == base_path(s.path) and not str.is_empty(t.auth) and t.auth != s.auth
        })
        if twinned {
          acc
        } else {
          list.concat(acc, [str.join([s.method, " ", base_path(s.path), " succeeds for one tenant but has no cross-tenant twin — add a scenario with the same method and path, a DIFFERENT tenant's Authorization header, expecting 404 (never 403: existence must not leak)"], "")])
        }
      } else {
        acc
      }
    }))
  }
}

fn coverage_errors(scenarios :: List[Probe]) -> List[Str] {
  list.concat(bare_route_errors(scenarios), twin_errors(scenarios))
}

