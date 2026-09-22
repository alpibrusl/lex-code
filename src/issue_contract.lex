# lex-code — implement from a typed issue (#173, lex-lang #949)
#
# A typed issue is the contract the manifesto asks an agent to work
# from — "a type signature, a set of examples, a set of properties" —
# rather than a codebase to imitate. `lex issue show <id>` hands back
# its declared acceptance; this module turns that into the task the
# build agent runs, and reads `lex issue verify`'s verdict back.
#
# Pure on purpose: everything that touches the CLI lives in the tools
# (src/tools/issue.lex) and the `--issue` entry point (src/tui/main.lex),
# so the rendering is covered by examples rather than by a live store.
#
# The acceptance, by shape (lex-store's `Acceptance`, serde tag "shape"):
#   typed_delta      api: [{name, signature, kind}], examples: [Str]
#   failing_example  example: Str   — fails at HEAD; fixed = passes
#   metric_invariant predicate, window — a window over the event log
#   evidence         subject, invariants — an attested chain
#   free_form        nothing — human-closed, the explicit exception

import "std.str" as str

import "std.list" as list

import "lex-schema/json_value" as jv

fn field_text(j :: jv.Json, key :: Str) -> Str {
  match jv.get_field(j, key) {
    None => "",
    Some(v) => match jv.as_str(v) {
      None => "",
      Some(s) => s,
    },
  }
}

fn field_list(j :: jv.Json, key :: Str) -> List[jv.Json] {
  match jv.get_field(j, key) {
    None => [],
    Some(v) => match jv.as_list(v) {
      None => [],
      Some(xs) => xs,
    },
  }
}

fn texts(xs :: List[jv.Json]) -> List[Str] {
  list.fold(xs, [], fn (acc :: List[Str], x :: jv.Json) -> List[Str] {
    match jv.as_str(x) {
      None => acc,
      Some(s) => list.concat(acc, [s]),
    }
  })
}

fn bullets(lines :: List[Str]) -> Str
  examples {
    bullets([]) => "",
    bullets(["a", "b"]) => "  - a\n  - b\n"
  }
{
  str.join(list.map(lines, fn (l :: Str) -> Str {
    str.join(["  - ", l, "\n"], "")
  }), "")
}

# One API entry as the declaration the store will compare against:
# `fn <name><signature>`. The gate compares whitespace-insensitively,
# but the model should still copy it verbatim.
fn api_line(entry :: jv.Json) -> Str {
  let kind := field_text(entry, "kind")
  let decl := str.join(["fn ", field_text(entry, "name"), field_text(entry, "signature")], "")
  if kind == "removed" {
    str.join(["REMOVE `", decl, "` — it must be absent at head"], "")
  } else {
    if kind == "changed" {
      str.join(["CHANGE to `", decl, "` — this exact signature at head"], "")
    } else {
      str.join(["ADD `", decl, "` — this exact signature at head"], "")
    }
  }
}

fn typed_delta_section(acc :: jv.Json) -> Str {
  let api := list.map(field_list(acc, "api"), api_line)
  let examples := texts(field_list(acc, "examples"))
  str.join(["Shape: typed_delta. The API delta is the contract:\n", bullets(api), if list.is_empty(examples) {
    ""
  } else {
    str.join(["These examples are the oracle — each must hold at head. Put them in the function's own `examples { }` block so the store's write-time gate runs them on every publish:\n", bullets(examples)], "")
  }], "")
}

fn failing_example_section(acc :: jv.Json) -> Str {
  str.join(["Shape: failing_example (a bug report). This example FAILS at head today; the issue is fixed when it passes:\n", bullets([field_text(acc, "example")]), "Fix the implementation, not the example. Add the example to the function's `examples { }` block so it cannot regress.\n"], "")
}

fn metric_section(acc :: jv.Json) -> Str {
  str.join(["Shape: metric_invariant. Predicate `", field_text(acc, "predicate"), "` must hold over the window `", field_text(acc, "window"), "`. The gate cannot evaluate this from code alone yet (it reports inconclusive); build what makes the predicate observable and true, and say what you could not verify.\n"], "")
}

fn evidence_section(acc :: jv.Json) -> Str {
  str.join(["Shape: evidence. Subject `", field_text(acc, "subject"), "` needs an attested chain satisfying:\n", bullets(texts(field_list(acc, "invariants"))), "The gate reports inconclusive for this shape today; say what evidence you produced.\n"], "")
}

fn free_form_section() -> Str {
  "Shape: free_form. There is no machine oracle — a human closes this issue. Work from the title and body, and end by proposing a typed acceptance (signatures + examples, or a failing example) that would have made it checkable.\n"
}

fn acceptance_section(acc :: jv.Json) -> Str {
  let shape := field_text(acc, "shape")
  if shape == "typed_delta" {
    typed_delta_section(acc)
  } else {
    if shape == "failing_example" {
      failing_example_section(acc)
    } else {
      if shape == "metric_invariant" {
        metric_section(acc)
      } else {
        if shape == "evidence" {
          evidence_section(acc)
        } else {
          free_form_section()
        }
      }
    }
  }
}

# Whether the gate can close this issue by itself. Mirrors lex-store's
# `Acceptance::is_machine_evaluable` for the shapes whose evaluator
# exists at head (typed_delta, failing_example); the other three verify
# as inconclusive today.
fn machine_closable(shape :: Str) -> Bool
  examples {
    machine_closable("typed_delta") => true,
    machine_closable("failing_example") => true,
    machine_closable("free_form") => false,
    machine_closable("metric_invariant") => false
  }
{
  shape == "typed_delta" or shape == "failing_example"
}

fn shape_of(issue :: jv.Json) -> Str {
  match jv.get_field(issue, "acceptance") {
    None => "free_form",
    Some(acc) => field_text(acc, "shape"),
  }
}

# The build task for an issue: `lex issue show --output json` in, the
# prompt the agent runs out.
fn contract_prompt(issue :: jv.Json) -> Str {
  let id := field_text(issue, "issue_id")
  let body := field_text(issue, "body")
  let shape := shape_of(issue)
  let acc := match jv.get_field(issue, "acceptance") {
    None => JObj([]),
    Some(a) => a,
  }
  let closing := if machine_closable(shape) {
    str.join(["\nDone is a proof, not a claim: call `issue_verify` with issue_id `", id, "` and iterate until its verdict is `verified`. A `failed` verdict's detail says exactly which signature or example is wrong. Every .lex file you write is published with this issue as its intent, so the ops link back to it.\n"], "")
  } else {
    str.join(["\nWhen finished, call `issue_verify` with issue_id `", id, "` to record the verdict (expect `inconclusive` for this shape). Every .lex file you write is published with this issue as its intent.\n"], "")
  }
  str.join(["Implement typed issue ", id, ": ", field_text(issue, "title"), "\n", if str.is_empty(str.trim(body)) {
    ""
  } else {
    str.join(["\n", body, "\n"], "")
  }, "\n", acceptance_section(acc), closing], "")
}

# `lex --output json issue verify` → the verdict word, or None when the
# command did not answer (unknown issue, no store). A `failed` verdict
# exits 1 but is still `"ok": true` — an answer, not an error.
fn verdict_of(stdout :: Str) -> Option[Str]
  examples {
    verdict_of("{\"ok\": true, \"data\": {\"verdict\": \"failed\", \"detail\": \"x\"}}") => Some("failed"),
    verdict_of("{\"ok\": true, \"data\": {\"verdict\": \"verified\"}}") => Some("verified"),
    verdict_of("{\"ok\": false, \"error\": {\"message\": \"unknown issue\"}}") => None,
    verdict_of("error: unknown command `issue`") => None
  }
{
  match jv.parse(str.trim(stdout)) {
    Err(_) => None,
    Ok(env) => match jv.get_field(env, "data") {
      None => None,
      Some(data) => match jv.get_field(data, "verdict") {
        None => None,
        Some(v) => jv.as_str(v),
      },
    },
  }
}

