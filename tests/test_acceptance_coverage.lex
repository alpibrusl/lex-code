# Tests for the acceptance-file coverage rules (src/package_flow/acceptance_rules).
#
# A built package once passed 18 of 18 acceptance scenarios and still answered
# 500 to a plain `GET /jobs` (its only listing scenario carried a query string),
# and another let one tenant "pay" another tenant's invoice (no scenario asked).
# These rules reject an acceptance file that leaves either case unasked. Each
# check below has its opposite next to it, so a rule that rejects everything, or
# nothing, fails here.

import "std.list" as list

import "std.io" as io

import "std.str" as str

import "../src/package_flow/acceptance_rules" as rules

fn check(name :: Str, cond :: Bool) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(name)
  }
}

fn p(method :: Str, path :: Str, auth :: Str, status :: Int) -> rules.Probe {
  { method: method, path: path, status: status, auth: auth }
}

fn mentions(ps :: List[Str], needle :: Str) -> Bool {
  list.fold(ps, false, fn (f :: Bool, x :: Str) -> Bool {
    f or str.contains(x, needle)
  })
}

fn test_query_only_route_is_rejected() -> Result[Unit, Str] {
  let ps := rules.coverage_errors([p("GET", "/jobs", "", 401), p("GET", "/jobs?state=done", "A", 200), p("GET", "/health", "", 200)])
  check("a 2xx route only ever called with a query string is rejected", mentions(ps, "GET /jobs is only exercised with a query string"))
}

fn test_bare_route_accepted() -> Result[Unit, Str] {
  let ps := rules.coverage_errors([p("GET", "/jobs", "", 401), p("GET", "/jobs?state=done", "A", 200), p("GET", "/jobs", "A", 200)])
  check("the same file with a bare call is clean", list.is_empty(ps))
}

fn test_a_401_does_not_count_as_the_bare_call() -> Result[Unit, Str] {
  let ps := rules.coverage_errors([p("GET", "/jobs", "", 401), p("GET", "/jobs?state=done", "A", 200)])
  check("the bare call must be a 2xx; a bare 401 does not cover it", mentions(ps, "GET /jobs"))
}

fn test_missing_twin_is_rejected() -> Result[Unit, Str] {
  let ps := rules.coverage_errors([p("GET", "/jobs/1", "A", 200), p("GET", "/jobs/1", "B", 404), p("POST", "/jobs/1/claim", "A", 200), p("GET", "/jobs", "B", 200)])
  check("a 2xx on an id with no other-tenant 404 twin is rejected", mentions(ps, "POST /jobs/1/claim succeeds for one tenant but has no cross-tenant twin"))
}

fn test_twinned_routes_are_accepted() -> Result[Unit, Str] {
  let ps := rules.coverage_errors([p("GET", "/jobs/1", "A", 200), p("GET", "/jobs/1", "B", 404), p("POST", "/jobs/1/claim", "B", 404), p("POST", "/jobs/1/claim", "A", 200), p("GET", "/jobs", "B", 200)])
  check("every id-bearing 2xx has its twin: clean", list.is_empty(ps))
}

fn test_twin_for_get_does_not_cover_post() -> Result[Unit, Str] {
  let ps := rules.coverage_errors([p("GET", "/jobs/1", "A", 200), p("GET", "/jobs/1", "B", 404), p("POST", "/jobs/1/claim", "A", 200), p("GET", "/jobs", "A", 200)])
  check("a twin for GET does not stand in for POST", mentions(ps, "POST /jobs/1/claim") and not mentions(ps, "GET /jobs/1 "))
}

fn test_single_tenant_has_no_twin_rule() -> Result[Unit, Str] {
  let ps := rules.coverage_errors([p("GET", "/things/1", "A", 200), p("GET", "/things", "", 401), p("GET", "/things", "A", 200)])
  check("one token only: no tenant to twin against, so none demanded", list.is_empty(ps))
}

fn test_same_token_is_not_a_twin() -> Result[Unit, Str] {
  let ps := rules.coverage_errors([p("GET", "/jobs/1", "A", 200), p("GET", "/jobs/1", "A", 404), p("GET", "/jobs", "B", 200)])
  check("a 404 from the SAME token is not a cross-tenant twin", mentions(ps, "GET /jobs/1 succeeds for one tenant"))
}

fn test_the_jobs_acceptance_file_that_missed_both() -> Result[Unit, Str] {
  let jobs := [p("GET", "/jobs", "", 401), p("GET", "/jobs", "Bearer nope", 401), p("GET", "/jobs", "Basic abc", 401), p("POST", "/jobs", "Bearer tokA", 201), p("GET", "/jobs/1", "Bearer tokA", 200), p("GET", "/jobs/1", "Bearer tokB", 404), p("GET", "/jobs/999", "Bearer tokB", 404), p("POST", "/jobs/1/claim", "Bearer tokA", 200), p("POST", "/jobs/1/claim", "Bearer tokA", 409), p("POST", "/jobs/1/complete", "Bearer tokA", 200), p("POST", "/jobs/1/complete", "Bearer tokA", 409), p("GET", "/jobs?state=done&limit=20", "Bearer tokA", 200), p("GET", "/jobs?state=queued' OR '1'='1", "Bearer tokA", 400)]
  let ps := rules.coverage_errors(jobs)
  check("the real jobs file (18/18, yet GET /jobs was 500) is rejected: bare list, claim twin, complete twin", list.len(ps) == 3 and mentions(ps, "GET /jobs is only exercised") and mentions(ps, "POST /jobs/1/claim succeeds") and mentions(ps, "POST /jobs/1/complete succeeds"))
}

fn suite() -> List[Result[Unit, Str]] {
  [test_the_jobs_acceptance_file_that_missed_both(), test_query_only_route_is_rejected(), test_bare_route_accepted(), test_a_401_does_not_count_as_the_bare_call(), test_missing_twin_is_rejected(), test_twinned_routes_are_accepted(), test_twin_for_get_does_not_cover_post(), test_single_tenant_has_no_twin_rule(), test_same_token_is_not_a_twin()]
}

fn run_all() -> [io] Unit {
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

