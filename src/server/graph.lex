# lex-code — agent graphs
#
# `multi_agent.lex` had three pipelines written out by hand, each one a
# fixed arrangement of the same two moves: run these in order, run these
# at once. #26 asks for those two moves to be values, so a new pipeline
# is a composition rather than a new function.
#
#   Node = AgentNode | SequenceNode | ParallelNode
#
# The three presets stay, as named constructors over the same runner, so
# nothing that used them changes behaviour.
#
# ---- why nodes are named ---------------------------------------------
#
# Every agent in the old runner opened its session as "worker". Nothing
# collided on disk — `new_session_with_provider` uses an in-memory log —
# but the id is not inert any more. #16 derives a trace id from it, so two
# agents running in parallel reported their spans under one trace, as if
# one agent had done both pieces of work. A node's name is its session id
# here, which separates them without a new concept.

import "lex-llm/delta" as d

import "lex-trail/log" as trail_log

import "lex-trail/event" as trail_ev

import "lex-trail/kinds" as kinds

import "std.list" as list

import "std.str" as str

import "std.int" as int

import "std.time" as time

import "std.process" as proc

import "./session" as sess

import "../verification" as verification

# `task_prefix` is what the old runner did inline — `"Write unit tests
# for: " ++ task`. Making it a field is what lets a caller build a node
# for work the presets never anticipated.
type AgentDef = { name :: Str, mode :: sess.AgentMode, task_prefix :: Str }

# `setup` runs once, unconditionally (typically build → test). Then
# `verify_program`/`verify_args` — a real subprocess, e.g. `lex test
# tests` — decides pass/fail by exit code, never by asking the fixing
# agent whether it thinks it's done: the same "mechanical, not LLM-judged"
# rule task_spec.lex already applies to one task's SuccessCriterion,
# extended across retries here. On failure, `fix` re-runs (up to
# `max_rounds` times) with the verification command's own output appended
# to the task, so the model sees the actual failure rather than being
# asked to guess what might be wrong.
#
# `lex test <dir>`, not `lex run <dir> run_all`: `lex run` has no
# directory support at all — `read_program` opens whatever path string
# it's given as a single file, so a bare directory fails with a raw OS
# "Is a directory" error regardless of what's inside. `lex_test.lex`'s
# tool carried this exact bug (default `path: "tests"`, executed as `lex
# run tests run_all`) until a live fix-loop run hit it: the mechanical
# verify step failed with that same opaque OS error on every round,
# masking a real, fixable bug in the file it never actually got to look
# at. `lex test` is the real native subcommand for "run every
# tests/test_*.lex file, calling run_all in each" (`lex introspect`'s own
# description) and correctly takes a directory.
#
# `verify_agent`, when `Some`, names an extra gate that runs once
# `verify_program` exits 0: `verify_found_failure` below explains why a
# passing mechanical check is not the same claim as a passing independent
# one. `None` preserves every existing preset's behaviour exactly.
type FixLoopDef = { setup :: Node, fix :: AgentDef, verify_program :: Str, verify_args :: List[Str], max_rounds :: Int, verify_agent :: Option[AgentDef] }

type Node = AgentNode(AgentDef) | SequenceNode(List[Node]) | ParallelNode(List[Node]) | FixLoopNode(FixLoopDef)

type NodeResult = { name :: Str, steps :: List[d.Step] }

type GraphResult = { results :: List[NodeResult] }

fn shape(def :: AgentDef, task :: Str) -> Str
  examples {
    shape({ name: "impl", mode: Build, task_prefix: "" }, "add zip") => "add zip",
    shape({ name: "test", mode: Test, task_prefix: "Write unit tests for: " }, "add zip") => "Write unit tests for: add zip"
  }
{
  str.concat(def.task_prefix, task)
}

# ---- the presets, as values ------------------------------------------
fn build_def() -> AgentDef {
  { name: "impl", mode: Build, task_prefix: "" }
}

fn spec_def() -> AgentDef {
  { name: "spec", mode: Spec, task_prefix: "Write lex-spec Spec for: " }
}

fn test_def() -> AgentDef {
  { name: "test", mode: Test, task_prefix: "Write unit tests for: " }
}

fn review_def() -> AgentDef {
  { name: "review", mode: Review, task_prefix: "Review implementation: " }
}

# Distinct from `review_def`: review audits structure and trust (effects,
# attestations, SigIds). Verify re-derives the expected output from the
# task's own spec and checks the implementation against that — a
# different question, and not one `review`'s toolset (no `write`, so it
# could never author its own check) can answer.
fn verify_def() -> AgentDef {
  { name: "verify", mode: Verify, task_prefix: "Independently verify: " }
}

fn impl_then_test() -> Node {
  SequenceNode([AgentNode(build_def()), AgentNode(test_def())])
}

fn impl_and_test_parallel() -> Node {
  ParallelNode([AgentNode(build_def()), AgentNode(test_def())])
}

fn impl_then_spec_then_test() -> Node {
  SequenceNode([AgentNode(build_def()), AgentNode(spec_def()), ParallelNode([AgentNode(test_def()), AgentNode(review_def())])])
}

# #120's "one-command full verify": build, then spec, then test, then
# review — each stage strictly after the last, unlike
# impl_then_spec_then_test's parallel test/review tail. review here
# reviews what test already checked, not the same untested output test
# is concurrently checking.
fn full_verify() -> Node {
  SequenceNode([AgentNode(build_def()), AgentNode(spec_def()), AgentNode(test_def()), AgentNode(review_def())])
}

# impl → test → verify, strictly sequential: verify runs last precisely
# because it needs something to check — an implementation and a test
# file already on disk, which it treats as two independent claims to
# re-derive and check, not two sources of truth to trust.
fn impl_then_test_then_verify() -> Node {
  SequenceNode([AgentNode(build_def()), AgentNode(test_def()), AgentNode(verify_def())])
}

# impl → test, then up to 2 retries: run `lex test tests` and, on a
# nonzero exit, feed its actual output back to a fresh `impl` turn instead
# of stopping. Manually verified end to end on a real bug (lex-rlp's RLP
# single-byte shortcut, asymmetric between encode and decode): a fresh
# build turn given the exact failing hex diagnosed and fixed it, and an
# independent re-verify confirmed every vector passed — that pass used a
# human pointing at the failure, not this loop; an automated attempt with
# `lex run tests run_all` (see `FixLoopDef`'s comment) never got past the
# broken verify command's opaque error, across two separate live runs, to
# find out whether the loop itself helps. Retest once the `lex test` fix
# is in. 2 rounds: each is a paid, unbounded-length agent turn — like the
# other presets' own per-agent cost, not the VM's free-to-raise compute
# ceiling — so an agent that can't fix its own bug in two pointed attempts
# should stop and surface the failure, not spend indefinitely.
fn impl_test_fix_loop() -> Node {
  FixLoopNode({ setup: SequenceNode([AgentNode(build_def()), AgentNode(test_def())]), fix: build_def(), verify_program: "lex", verify_args: ["test", "tests"], max_rounds: 2, verify_agent: None })
}

# Same loop, plus an independent verify pass once `lex test tests` exits 0.
# Validated live (2026-09-08) against a known-buggy lex-abi encode_call: a
# fixing agent can pass its own test file while the test file's expected
# value is itself wrong — the same class of bug this session found twice,
# once as a lex-lang compiler bug (vacuous pass on an empty test dir, fixed
# upstream in v0.10.17) and once as a mistyped hex literal in an
# implementation's own tests/. `lex test` exiting 0 cannot distinguish
# either case from a genuinely correct implementation; verify re-derives
# the expected values itself and never touches the implementation or its
# tests (rules.verify_permission has no edit/bash), so a FAIL it reports is
# a different kind of evidence, not a second opinion on the same one.
# Shares `max_rounds` with the mechanical gate rather than a separate
# budget — one shared "keep fixing until both agree" retry count, simplest
# thing that expresses the requirement.
fn impl_test_fix_loop_verified() -> Node {
  FixLoopNode({ setup: SequenceNode([AgentNode(build_def()), AgentNode(test_def())]), fix: build_def(), verify_program: "lex", verify_args: ["test", "tests"], max_rounds: 2, verify_agent: Some(verify_def()) })
}

fn preset_names() -> List[Str]
  examples {
    preset_names() => ["impl_then_test", "impl_and_test_parallel", "impl_then_spec_then_test", "full_verify", "impl_then_test_then_verify", "impl_test_fix_loop", "impl_test_fix_loop_verified"]
  }
{
  ["impl_then_test", "impl_and_test_parallel", "impl_then_spec_then_test", "full_verify", "impl_then_test_then_verify", "impl_test_fix_loop", "impl_test_fix_loop_verified"]
}

# Resolve a pipeline name from the command line. Unknown names are None
# rather than a silent fallback to a default: running a different pipeline
# than the one asked for is worse than refusing.
fn preset(name :: Str) -> Option[Node] {
  if name == "impl_then_test" {
    Some(impl_then_test())
  } else {
    if name == "impl_and_test_parallel" {
      Some(impl_and_test_parallel())
    } else {
      if name == "impl_then_spec_then_test" {
        Some(impl_then_spec_then_test())
      } else {
        if name == "full_verify" {
          Some(full_verify())
        } else {
          if name == "impl_then_test_then_verify" {
            Some(impl_then_test_then_verify())
          } else {
            if name == "impl_test_fix_loop" {
              Some(impl_test_fix_loop())
            } else {
              if name == "impl_test_fix_loop_verified" {
                Some(impl_test_fix_loop_verified())
              } else {
                None
              }
            }
          }
        }
      }
    }
  }
}

# What a name actually resolves to. `is_preset` only proves a name maps to
# something; this proves it maps to the right thing, which is the mistake
# a lookup table invites — swap two arms and every caller still gets a
# valid pipeline, just not the one it asked for.
fn preset_shape(name :: Str) -> Str
  examples {
    preset_shape("impl_then_test") => "impl → test",
    preset_shape("impl_and_test_parallel") => "impl ∥ test",
    preset_shape("impl_then_spec_then_test") => "impl → spec → (test ∥ review)",
    preset_shape("full_verify") => "impl → spec → test → review",
    preset_shape("impl_then_test_then_verify") => "impl → test → verify",
    preset_shape("impl_test_fix_loop") => "impl → test ⟳×2",
    preset_shape("impl_test_fix_loop_verified") => "impl → test ⟳×2 → verify",
    preset_shape("nope") => ""
  }
{
  match preset(name) {
    None => "",
    Some(n) => render_shape(n),
  }
}

fn is_preset(name :: Str) -> Bool
  examples {
    is_preset("impl_then_test") => true,
    is_preset("impl_and_test_parallel") => true,
    is_preset("impl_then_spec_then_test") => true,
    is_preset("full_verify") => true,
    is_preset("impl_then_test_then_verify") => true,
    is_preset("impl_test_fix_loop") => true,
    is_preset("impl_test_fix_loop_verified") => true,
    is_preset("build") => false,
    is_preset("") => false
  }
{
  match preset(name) {
    None => false,
    Some(_) => true,
  }
}

# The exact prompt each preset agent receives, pinned against the strings
# the hand-written runner used. #26's acceptance is that the presets behave
# as before, and the prefix is the only part of that a refactor can move
# silently: shape() and the node graph can both be right while an agent is
# asked for something subtly different. Mutating any prefix fails here.
fn preset_prompts(task :: Str) -> List[Str]
  examples {
    preset_prompts("add zip") => ["add zip", "Write lex-spec Spec for: add zip", "Write unit tests for: add zip", "Review implementation: add zip"]
  }
{
  [shape(build_def(), task), shape(spec_def(), task), shape(test_def(), task), shape(review_def(), task)]
}

# ---- ad-hoc pipelines -------------------------------------------------
#
# #26 gave three presets by name. #30 wants a pipeline assembled on the
# command line — `--pipeline=build,spec,test` — so a run is not limited to
# arrangements someone thought to name.
#
# The grammar is two characters: `,` sequences, `|` runs in parallel.
# `build,spec,test|review` is impl_then_spec_then_test, which is the test
# that the two halves agree.
fn agent_for(name :: Str) -> Option[AgentDef] {
  if name == "build" {
    Some(build_def())
  } else {
    if name == "impl" {
      Some(build_def())
    } else {
      if name == "spec" {
        Some(spec_def())
      } else {
        if name == "test" {
          Some(test_def())
        } else {
          if name == "review" {
            Some(review_def())
          } else {
            if name == "verify" {
              Some(verify_def())
            } else {
              None
            }
          }
        }
      }
    }
  }
}

fn agent_names_accepted() -> List[Str]
  examples {
    agent_names_accepted() => ["build", "impl", "spec", "test", "review", "verify"]
  }
{
  ["build", "impl", "spec", "test", "review", "verify"]
}

# One `|`-separated stage: a single agent, or several run at once.
fn stage_of(seg :: Str) -> Result[Node, Str] {
  let parts := list.map(str.split(seg, "|"), fn (x :: Str) -> Str {
    str.trim(x)
  })
  match fold_agents(parts, []) {
    Err(m) => Err(m),
    Ok(nodes) => if list.len(nodes) == 1 {
      match list.head(nodes) {
        None => Err("empty stage"),
        Some(n) => Ok(n),
      }
    } else {
      Ok(ParallelNode(nodes))
    },
  }
}

fn fold_agents(names :: List[Str], acc :: List[Node]) -> Result[List[Node], Str] {
  match list.head(names) {
    None => Ok(list.reverse(acc)),
    Some(n) => match agent_for(n) {
      None => Err(str.join(["unknown agent \"", n, "\" — try one of: ", str.join(agent_names_accepted(), ", ")], "")),
      Some(def) => fold_agents(list.tail(names), list.cons(AgentNode(def), acc)),
    },
  }
}

fn fold_stages(segs :: List[Str], acc :: List[Node]) -> Result[List[Node], Str] {
  match list.head(segs) {
    None => Ok(list.reverse(acc)),
    Some(seg) => match stage_of(seg) {
      Err(m) => Err(m),
      Ok(node) => fold_stages(list.tail(segs), list.cons(node, acc)),
    },
  }
}

# Parse a pipeline spec. An unknown agent name is refused with the list of
# valid ones rather than skipped: a pipeline silently missing a stage is a
# run that looks successful and did less than it was asked to.
fn from_spec(spec :: Str) -> Result[Node, Str] {
  let segs := list.map(str.split(str.trim(spec), ","), fn (x :: Str) -> Str {
    str.trim(x)
  })
  if str.is_empty(str.trim(spec)) {
    Err("empty pipeline spec")
  } else {
    match fold_stages(segs, []) {
      Err(m) => Err(m),
      Ok(nodes) => if list.len(nodes) == 1 {
        match list.head(nodes) {
          None => Err("empty pipeline spec"),
          Some(n) => Ok(n),
        }
      } else {
        Ok(SequenceNode(nodes))
      },
    }
  }
}

# What a spec parses to, as a shape string — so the grammar is pinned by
# examples rather than described in a comment. The third case is the one
# that matters: it must equal the impl_then_spec_then_test preset.
fn spec_shape(spec :: Str) -> Str
  examples {
    spec_shape("build,test") => "impl → test",
    spec_shape("build|test") => "impl ∥ test",
    spec_shape("build,spec,test|review") => "impl → spec → (test ∥ review)",
    spec_shape("impl") => "impl",
    spec_shape("build, spec") => "impl → spec",
    spec_shape("nope") => "unknown agent \"nope\" — try one of: build, impl, spec, test, review, verify",
    spec_shape("") => "empty pipeline spec"
  }
{
  match from_spec(spec) {
    Err(m) => m,
    Ok(n) => render_shape(n),
  }
}

# A spec and the named preset it reproduces must not drift apart.
fn spec_matches_preset() -> Bool
  examples {
    spec_matches_preset() => true
  }
{
  if spec_shape("build,test") == preset_shape("impl_then_test") {
    if spec_shape("build|test") == preset_shape("impl_and_test_parallel") {
      if spec_shape("build,spec,test|review") == preset_shape("impl_then_spec_then_test") {
        if spec_shape("build,spec,test,review") == preset_shape("full_verify") {
          spec_shape("build,test,verify") == preset_shape("impl_then_test_then_verify")
        } else {
          false
        }
      } else {
        false
      }
    } else {
      false
    }
  } else {
    false
  }
}

# ---- shape queries (pure, so they can carry examples) ------------------
# A `FixLoopNode` counts `max_rounds` retries on top of `setup`, plus one
# more when `verify_agent` is set — an upper bound, since a passing
# mechanical check and a passing verify both stop the loop early and run
# fewer than the worst case.
fn node_count(n :: Node) -> Int
  examples {
    node_count(AgentNode({ name: "a", mode: Build, task_prefix: "" })) => 1,
    node_count(SequenceNode([])) => 0,
    node_count(impl_then_test()) => 2,
    node_count(impl_then_spec_then_test()) => 4,
    node_count(impl_test_fix_loop()) => 4,
    node_count(impl_test_fix_loop_verified()) => 5
  }
{
  match n {
    AgentNode(_) => 1,
    SequenceNode(kids) => count_all(kids),
    ParallelNode(kids) => count_all(kids),
    FixLoopNode(def) => node_count(def.setup) + def.max_rounds + verify_extra(def),
  }
}

# `verify_agent`'s worst-case contribution to `node_count`: at most one
# more call than the mechanical retries already counted, since verify
# only ever runs after a round's mechanical check has passed (never
# alongside a mechanical retry) and a single failing verify consumes one
# of the SAME `max_rounds` budget already accounted for above, not an
# additional one.
fn verify_extra(def :: FixLoopDef) -> Int
  examples {
    verify_extra({ setup: SequenceNode([]), fix: build_def(), verify_program: "lex", verify_args: [], max_rounds: 2, verify_agent: None }) => 0,
    verify_extra({ setup: SequenceNode([]), fix: build_def(), verify_program: "lex", verify_args: [], max_rounds: 2, verify_agent: Some(verify_def()) }) => 1
  }
{
  match def.verify_agent {
    None => 0,
    Some(_) => 1,
  }
}

fn count_all(kids :: List[Node]) -> Int {
  list.fold(kids, 0, fn (acc :: Int, k :: Node) -> Int {
    acc + node_count(k)
  })
}

# `FixLoopNode` reports only `setup`'s names: the retry rounds (and
# `verify_agent`, when set) are runtime-conditional (0 to `max_rounds` of
# them actually run, depending on whether the mechanical check and verify
# both pass), not part of the pipeline's static shape.
fn agent_names(n :: Node) -> List[Str]
  examples {
    agent_names(impl_then_test()) => ["impl", "test"],
    agent_names(impl_then_spec_then_test()) => ["impl", "spec", "test", "review"],
    agent_names(impl_test_fix_loop()) => ["impl", "test"],
    agent_names(impl_test_fix_loop_verified()) => ["impl", "test"],
    agent_names(SequenceNode([])) => []
  }
{
  match n {
    AgentNode(def) => [def.name],
    SequenceNode(kids) => names_all(kids),
    ParallelNode(kids) => names_all(kids),
    FixLoopNode(def) => agent_names(def.setup),
  }
}

fn names_all(kids :: List[Node]) -> List[Str] {
  list.fold(kids, [], fn (acc :: List[Str], k :: Node) -> List[Str] {
    list.concat(acc, agent_names(k))
  })
}

# A flat name list cannot tell a sequence from a parallel branch — both
# read as "impl, test" — which would let the TUI announce a pipeline it is
# not about to run. The separators carry the structure instead.
fn render_shape(n :: Node) -> Str
  examples {
    render_shape(impl_then_test()) => "impl → test",
    render_shape(impl_and_test_parallel()) => "impl ∥ test",
    render_shape(impl_then_spec_then_test()) => "impl → spec → (test ∥ review)",
    render_shape(impl_test_fix_loop()) => "impl → test ⟳×2",
    render_shape(impl_test_fix_loop_verified()) => "impl → test ⟳×2 → verify",
    render_shape(AgentNode({ name: "solo", mode: Build, task_prefix: "" })) => "solo",
    render_shape(SequenceNode([])) => ""
  }
{
  match n {
    AgentNode(def) => def.name,
    SequenceNode(kids) => join_kids(kids, " → "),
    ParallelNode(kids) => join_kids(kids, " ∥ "),
    FixLoopNode(def) => fix_loop_shape(def),
  }
}

fn fix_loop_shape(def :: FixLoopDef) -> Str {
  let base := str.join([render_shape(def.setup), " ⟳×", int.to_str(def.max_rounds)], "")
  match def.verify_agent {
    None => base,
    Some(vdef) => str.join([base, " → ", vdef.name], ""),
  }
}

# A nested branch is parenthesised so the grouping survives flattening;
# a top-level one does not need it, which is why the wrapping happens in
# the child rather than in the parent.
fn join_kids(kids :: List[Node], sep :: Str) -> Str {
  str.join(list.map(kids, fn (k :: Node) -> Str {
    wrap(k)
  }), sep)
}

fn wrap(n :: Node) -> Str {
  match n {
    AgentNode(def) => def.name,
    SequenceNode(kids) => paren(join_kids(kids, " → ")),
    ParallelNode(kids) => paren(join_kids(kids, " ∥ ")),
    FixLoopNode(def) => paren(fix_loop_shape(def)),
  }
}

fn paren(inner :: Str) -> Str
  examples {
    paren("a → b") => "(a → b)",
    paren("") => ""
  }
{
  if str.is_empty(inner) {
    ""
  } else {
    str.join(["(", inner, ")"], "")
  }
}

# ---- the runner -------------------------------------------------------
fn run_graph(root :: Node, task :: Str, provider_tag :: Str) -> [env, concurrent, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] GraphResult {
  { results: run_node(root, task, provider_tag) }
}

# `concurrent` sits in this row whether or not the graph has a
# ParallelNode: the row is a property of the function, not of the value it
# is handed, and a runner that could not run a parallel node would not be
# a graph runner. A purely sequential graph simply never uses it.
fn run_node(n :: Node, task :: Str, provider_tag :: Str) -> [env, concurrent, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] List[NodeResult] {
  match n {
    AgentNode(def) => [run_agent(def, task, provider_tag)],
    SequenceNode(kids) => list.fold(kids, [], fn (acc :: List[NodeResult], k :: Node) -> [env, concurrent, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] List[NodeResult] {
      list.concat(acc, run_node(k, task, provider_tag))
    }),
    ParallelNode(kids) => list.fold(list.par_map(kids, fn (k :: Node) -> [env, concurrent, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] List[NodeResult] {
      run_node(k, task, provider_tag)
    }), [], fn (acc :: List[NodeResult], rs :: List[NodeResult]) -> List[NodeResult] {
      list.concat(acc, rs)
    }),
    FixLoopNode(def) => run_fix_loop(def, task, provider_tag),
  }
}

# A failed session start yields an empty step list under the node's own
# name rather than dropping the node, so the result list always lines up
# with the graph that produced it. A caller counting results against
# `agent_names` would otherwise silently mis-attribute every later node.
fn run_agent(def :: AgentDef, task :: Str, provider_tag :: Str) -> [env, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] NodeResult {
  match sess.new_session_with_provider(def.name, def.mode, provider_tag) {
    Err(_) => { name: def.name, steps: [] },
    Ok(session) => {
      let result := sess.run_turn_with_provider(session, shape(def, task), provider_tag)
      { name: def.name, steps: result.steps }
    },
  }
}

# Same as `run_agent`, but also hands back the turn's trail events —
# needed only by the fix loop's verify gate, which has to read a tool
# result it did not itself dispatch (see `tool_result_texts`'s comment for
# why `Session.messages`/`d.Step` cannot supply this). Every other caller
# uses `run_agent`/`run_agent_persistent`, which discard the session
# because nothing else needs anything past `NodeResult`.
#
# `trail_log.range` reads events by timestamp window, not by session —
# the same connection two callers query with two different windows sees
# only their own turn's events, but a query wide enough to span BOTH
# would see both. `started`/`ended` bracket exactly this one turn, so
# that is only a hazard for calls sharing a log AND overlapping in time,
# which nothing here does (rounds run strictly one after another).
fn run_agent_with_events(def :: AgentDef, task :: Str, provider_tag :: Str) -> [env, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] (NodeResult, List[trail_ev.Event]) {
  match sess.new_session_with_provider(def.name, def.mode, provider_tag) {
    Err(_) => ({ name: def.name, steps: [] }, []),
    Ok(session) => {
      let started := time.now_ms()
      let result := sess.run_turn_with_provider(session, shape(def, task), provider_tag)
      let ended := time.now_ms()
      match trail_log.range(result.session.log, started, ended) {
        Err(_) => ({ name: def.name, steps: result.steps }, []),
        Ok(events) => {
          let __attested := attest_verify_pass_if_clean(result.session.log, events)
          ({ name: def.name, steps: result.steps }, events)
        },
      }
    },
  }
}

# lex-code#32: verify mode's own pass is never one of lex-llm's `verified.*`
# kinds — `lex_run` (what verify's own convention runs its checks through)
# isn't a tool `verified_kind_for_tool` recognizes, and it shouldn't be
# recognized generically there either: an ordinary build-mode `lex_run`
# passing proves nothing, only a VERIFY-mode one that found no FAIL does.
# So a clean pass here — the strongest evidence in the whole system, an
# independent re-derivation that never trusted the implementation — left
# no durable trace for a later `review` agent or `task_spec.lex` criterion
# to find. Attest it directly, reusing `verification.lex`'s own
# Record/harvest/append_all rather than inventing a second mechanism.
#
# Guarded on "did this turn's tool output actually contain a `lex_run`
# result at all", not just "no FAIL found in it" — a session that errored
# out before running anything has an empty event list, and `false` is the
# vacuous, wrong answer to "did verify find a failure" for that case. Same
# trap `lex test`'s own empty-directory bug taught this session to guard
# against (lex-lang v0.10.17); the fix here is the same shape.
fn attest_verify_pass_if_clean(log :: trail_log.Log, events :: List[trail_ev.Event]) -> [io, sql, time] Unit {
  if list.is_empty(tool_result_texts(events)) {
    ()
  } else {
    if verify_found_failure(events) {
      ()
    } else {
      match trail_log.append(log, independent_check_kind(), None, "{\"tool\":\"lex_run\",\"target\":\"\",\"result\":\"pass\"}") {
        Err(_) => (),
        Ok(evt) => {
          let __promoted := verification.append_all(verification.harvest(log, evt.ts_ms, evt.ts_ms + 1))
          ()
        },
      }
    }
  }
}

fn independent_check_kind() -> Str
  examples {
    independent_check_kind() => "verified.independent_check"
  }
{
  "verified.independent_check"
}

# ---- the fix loop -------------------------------------------------------
#
# Runs `setup` once, then mechanically verifies with a real subprocess —
# never the fixing agent's own self-report. `round_name` gives each retry
# a distinct session id: the persistent variant writes one trail file per
# id, and reusing "impl" across rounds would hit the exact stale
# `event_count` collision #91 found — a later round's fresh session
# colliding with an earlier round's id on disk.
fn round_name(base :: Str, round :: Int) -> Str
  examples {
    round_name("impl", 0) => "impl",
    round_name("impl", 1) => "impl_retry1",
    round_name("impl", 2) => "impl_retry2"
  }
{
  if round == 0 {
    base
  } else {
    str.join([base, "_retry", int.to_str(round)], "")
  }
}

# A retry's task must not grow unboundedly across rounds — the verify
# command's own combined stdout+stderr is capped, same idiom as
# `bash.lex`'s `truncate_output` for a tool result.
fn max_fix_context_chars() -> Int {
  4000
}

fn truncate_for_prompt(s :: Str) -> Str {
  let len := str.len(s)
  if len <= max_fix_context_chars() {
    s
  } else {
    str.join([str.slice(s, 0, max_fix_context_chars()), "\n\n[... verification output truncated: ", int.to_str(len), " total characters ...]"], "")
  }
}

fn fix_task(task :: Str, def :: FixLoopDef, out :: { stdout :: Str, stderr :: Str, exit_code :: Int }) -> Str {
  str.join([task, "\n\nA previous attempt at this task exists in the working directory, but verification failed.\nCommand: ", def.verify_program, " ", str.join(def.verify_args, " "), "\nExit code: ", int.to_str(out.exit_code), "\nOutput:\n", truncate_for_prompt(str.concat(out.stdout, out.stderr)), "\n\nFind and fix the bug that caused this failure. Do not rewrite unrelated working code."], "")
}

# ---- verify as a gate ---------------------------------------------------
#
# `verify_program` exiting 0 is evidence the test file's own assertions
# held, not evidence they asserted the right thing — this session found
# both a compiler bug that made an empty test directory exit 0 (fixed
# upstream, lex-lang v0.10.17) and a mistyped expected value in an
# implementation's own tests/, either of which this mechanical gate alone
# cannot tell apart from a genuinely correct implementation. `verify_agent`
# re-derives the expected values independently instead of trusting
# anything on disk (rules.verify_permission has no edit/bash — it cannot
# quietly patch around what it finds), so a FAIL it reports is different
# evidence, not a second opinion on the same one.
#
# The pass/fail signal still has to come from a real artifact, same rule
# as the mechanical gate: never ask the verify agent (in its own
# free-form final response) whether it thinks things are fine.
# `prompts/verify.lex`'s own convention is to print each case's
# "OK <name>" / "FAIL <name> got=... want=..." via a real `lex_run`, not a
# prose verdict — validated live against lex-abi's encode_call (2026-09-08,
# after #144/#145/#146): the final run's own `lex_run` call literally
# printed "OK selector\nFAIL encode_call got=...".
#
# That text is NOT reachable from `TurnResult` at all — a first attempt at
# this reached for `Session.messages`' `ToolMsg` entries and shipped
# broken (#148), caught live in a controlled follow-up test: `finish_turn`
# (session.lex) only ever appends the turn's FINAL `StepDone` message to
# `session.messages`, never the `ToolMsg`s a mid-loop tool dispatch
# produces, so the scan silently saw zero text and no FAIL was ever
# detected. `d.Step` cannot help either — `StepToolResult` carries only
# `(call_id, success_bool)`, not the tool's returned content
# (`lex-llm/agent.lex`'s dispatcher constructs it from `disp.call.id`/
# `disp.success`, never the result body). The one place the text actually
# lands is the session's own trail (`Session.log`), which every tool
# dispatch appends a `cap.completed`/`cap.failed` event to as it happens
# (`lex-llm/agent.lex`'s `cap_completed_json`) — the same log this
# session's own manual `sqlite3 .../sessions/*.db` inspections read from
# throughout. Scanning it for "FAIL" inspects the same class of evidence
# as an exit code — a real subprocess's captured stdout — just recorded
# in the trail because verify's own file returns a rendered `Str` rather
# than calling `std.process.exit`; nothing about a Lex function's return
# value is meant to gate anything by itself, this loop is what turns its
# printed output into one.
fn tool_result_texts(events :: List[trail_ev.Event]) -> List[Str] {
  list.fold(events, [], fn (acc :: List[Str], e :: trail_ev.Event) -> List[Str] {
    if e.kind == kinds.cap_completed() and str.contains(e.payload_json, "\"lex_run\"") {
      list.concat(acc, [e.payload_json])
    } else {
      acc
    }
  })
}

fn verify_found_failure(events :: List[trail_ev.Event]) -> Bool
  examples {
    verify_found_failure([]) => false,
    verify_found_failure([trail_ev.make("cap.completed", None, "{\"capability\":\"lex_run\",\"result\":\"OK selector\\nOK encode_call\"}", 0)]) => false,
    verify_found_failure([trail_ev.make("cap.completed", None, "{\"capability\":\"lex_run\",\"result\":\"OK selector\\nFAIL encode_call got=x want=y\"}", 0)]) => true,
    verify_found_failure([trail_ev.make("cap.invoked", None, "{\"capability\":\"lex_run\",\"args\":{\"fn_name\":\"FAIL_looking_but_unrun\"}}", 0)]) => false
  }
{
  list.fold(tool_result_texts(events), false, fn (acc :: Bool, text :: Str) -> Bool {
    acc or str.contains(text, "FAIL")
  })
}

fn verify_fix_task(task :: Str, verify_events :: List[trail_ev.Event]) -> Str {
  str.join([task, "\n\nAn independent verification pass found a problem with the implementation. It re-derived the expected values itself rather than trusting the implementation's own tests, so this is not the same claim as a failing test.\nVerification output:\n", truncate_for_prompt(str.join(tool_result_texts(verify_events), "\n")), "\n\nFind and fix the bug that caused this. Do not rewrite unrelated working code, and do not edit the verification file itself."], "")
}

fn run_fix_loop(def :: FixLoopDef, task :: Str, provider_tag :: Str) -> [env, concurrent, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] List[NodeResult] {
  fix_round(def, task, provider_tag, 0, run_node(def.setup, task, provider_tag))
}

# `Err` from the verify command itself (not found, refused to run) stops
# the loop rather than looping forever on a command that can never
# succeed — an unrunnable check is not evidence the fix failed.
#
# Once the mechanical check passes, `verify_agent` (when set) gets one
# chance to find a problem the mechanical check couldn't see. A FAIL it
# reports is fed back to the SAME `fix` agent, from the SAME `max_rounds`
# budget as a mechanical failure — one shared "keep fixing until both
# agree" retry count, not a second one — and the next round re-checks the
# mechanical gate first, since a fix aimed at verify's finding could in
# principle have broken a test that was passing before.
fn fix_round(def :: FixLoopDef, task :: Str, provider_tag :: Str, round :: Int, acc :: List[NodeResult]) -> [env, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] List[NodeResult] {
  match proc.run(def.verify_program, def.verify_args) {
    Err(_) => acc,
    Ok(out) => if out.exit_code != 0 {
      if round >= def.max_rounds {
        acc
      } else {
        let next_round := round + 1
        let fix_def := { name: round_name(def.fix.name, next_round), mode: def.fix.mode, task_prefix: def.fix.task_prefix }
        let fix_result := run_agent(fix_def, fix_task(task, def, out), provider_tag)
        fix_round(def, task, provider_tag, next_round, list.concat(acc, [fix_result]))
      }
    } else {
      match def.verify_agent {
        None => acc,
        Some(vdef) => {
          let verify_def_r := { name: round_name(vdef.name, round), mode: vdef.mode, task_prefix: vdef.task_prefix }
          let verify_run := run_agent_with_events(verify_def_r, task, provider_tag)
          match verify_run {
            (verify_result, verify_events) => if verify_found_failure(verify_events) {
              if round >= def.max_rounds {
                list.concat(acc, [verify_result])
              } else {
                let next_round := round + 1
                let fix_def := { name: round_name(def.fix.name, next_round), mode: def.fix.mode, task_prefix: def.fix.task_prefix }
                let fix_result := run_agent(fix_def, verify_fix_task(task, verify_events), provider_tag)
                fix_round(def, task, provider_tag, next_round, list.concat(acc, [verify_result, fix_result]))
              }
            } else {
              list.concat(acc, [verify_result])
            },
          }
        },
      }
    },
  }
}

# ---- the auditable runner ----------------------------------------------
#
# Identical to run_graph/run_node/run_agent above except each node's session
# is persistent (sess.new_session_persistent_with_provider): the trail lands
# at `.lex/sessions/<node-name>.db` — "impl", "spec", "test", "review" for
# the standard presets — and survives the process exiting, so every tool
# dispatch and verified.* attestation across the whole pipeline can be
# audited afterward with lex-trail/log's range/head, not just observed live.
fn run_graph_persistent(root :: Node, task :: Str, provider_tag :: Str) -> [env, concurrent, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] GraphResult {
  { results: run_node_persistent(root, task, provider_tag) }
}

fn run_node_persistent(n :: Node, task :: Str, provider_tag :: Str) -> [env, concurrent, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] List[NodeResult] {
  match n {
    AgentNode(def) => [run_agent_persistent(def, task, provider_tag)],
    SequenceNode(kids) => list.fold(kids, [], fn (acc :: List[NodeResult], k :: Node) -> [env, concurrent, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] List[NodeResult] {
      list.concat(acc, run_node_persistent(k, task, provider_tag))
    }),
    ParallelNode(kids) => list.fold(list.par_map(kids, fn (k :: Node) -> [env, concurrent, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] List[NodeResult] {
      run_node_persistent(k, task, provider_tag)
    }), [], fn (acc :: List[NodeResult], rs :: List[NodeResult]) -> List[NodeResult] {
      list.concat(acc, rs)
    }),
    FixLoopNode(def) => run_fix_loop_persistent(def, task, provider_tag),
  }
}

fn run_fix_loop_persistent(def :: FixLoopDef, task :: Str, provider_tag :: Str) -> [env, concurrent, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] List[NodeResult] {
  fix_round_persistent(def, task, provider_tag, 0, run_node_persistent(def.setup, task, provider_tag))
}

fn fix_round_persistent(def :: FixLoopDef, task :: Str, provider_tag :: Str, round :: Int, acc :: List[NodeResult]) -> [env, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] List[NodeResult] {
  match proc.run(def.verify_program, def.verify_args) {
    Err(_) => acc,
    Ok(out) => if out.exit_code != 0 {
      if round >= def.max_rounds {
        acc
      } else {
        let next_round := round + 1
        let fix_def := { name: round_name(def.fix.name, next_round), mode: def.fix.mode, task_prefix: def.fix.task_prefix }
        let fix_result := run_agent_persistent(fix_def, fix_task(task, def, out), provider_tag)
        fix_round_persistent(def, task, provider_tag, next_round, list.concat(acc, [fix_result]))
      }
    } else {
      match def.verify_agent {
        None => acc,
        Some(vdef) => {
          let verify_def_r := { name: round_name(vdef.name, round), mode: vdef.mode, task_prefix: vdef.task_prefix }
          let verify_run := run_agent_persistent_with_events(verify_def_r, task, provider_tag)
          match verify_run {
            (verify_result, verify_events) => if verify_found_failure(verify_events) {
              if round >= def.max_rounds {
                list.concat(acc, [verify_result])
              } else {
                let next_round := round + 1
                let fix_def := { name: round_name(def.fix.name, next_round), mode: def.fix.mode, task_prefix: def.fix.task_prefix }
                let fix_result := run_agent_persistent(fix_def, verify_fix_task(task, verify_events), provider_tag)
                fix_round_persistent(def, task, provider_tag, next_round, list.concat(acc, [verify_result, fix_result]))
              }
            } else {
              list.concat(acc, [verify_result])
            },
          }
        },
      }
    },
  }
}

fn run_agent_persistent(def :: AgentDef, task :: Str, provider_tag :: Str) -> [env, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] NodeResult {
  match sess.new_session_persistent_with_provider(def.name, def.mode, provider_tag) {
    Err(_) => { name: def.name, steps: [] },
    Ok(session) => {
      let result := sess.run_turn_with_provider(session, shape(def, task), provider_tag)
      { name: def.name, steps: result.steps }
    },
  }
}

# Persistent counterpart to `run_agent_with_events` — see its comment.
fn run_agent_persistent_with_events(def :: AgentDef, task :: Str, provider_tag :: Str) -> [env, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] (NodeResult, List[trail_ev.Event]) {
  match sess.new_session_persistent_with_provider(def.name, def.mode, provider_tag) {
    Err(_) => ({ name: def.name, steps: [] }, []),
    Ok(session) => {
      let started := time.now_ms()
      let result := sess.run_turn_with_provider(session, shape(def, task), provider_tag)
      let ended := time.now_ms()
      match trail_log.range(result.session.log, started, ended) {
        Err(_) => ({ name: def.name, steps: result.steps }, []),
        Ok(events) => {
          let __attested := attest_verify_pass_if_clean(result.session.log, events)
          ({ name: def.name, steps: result.steps }, events)
        },
      }
    },
  }
}

# ---- reading a result -------------------------------------------------
fn steps_for(g :: GraphResult, name :: Str) -> List[d.Step] {
  match list.head(list.filter(g.results, fn (r :: NodeResult) -> Bool {
    r.name == name
  })) {
    None => [],
    Some(r) => r.steps,
  }
}

fn all_steps(g :: GraphResult) -> List[d.Step] {
  list.fold(g.results, [], fn (acc :: List[d.Step], r :: NodeResult) -> List[d.Step] {
    list.concat(acc, r.steps)
  })
}

