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

import "std.list" as list

import "std.str" as str

import "./session" as sess

# `task_prefix` is what the old runner did inline — `"Write unit tests
# for: " ++ task`. Making it a field is what lets a caller build a node
# for work the presets never anticipated.
type AgentDef = { name :: Str, mode :: sess.AgentMode, task_prefix :: Str }

type Node = AgentNode(AgentDef) | SequenceNode(List[Node]) | ParallelNode(List[Node])

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

fn impl_then_test() -> Node {
  SequenceNode([AgentNode(build_def()), AgentNode(test_def())])
}

fn impl_and_test_parallel() -> Node {
  ParallelNode([AgentNode(build_def()), AgentNode(test_def())])
}

fn impl_then_spec_then_test() -> Node {
  SequenceNode([AgentNode(build_def()), AgentNode(spec_def()), ParallelNode([AgentNode(test_def()), AgentNode(review_def())])])
}

fn preset_names() -> List[Str]
  examples {
    preset_names() => ["impl_then_test", "impl_and_test_parallel", "impl_then_spec_then_test"]
  }
{
  ["impl_then_test", "impl_and_test_parallel", "impl_then_spec_then_test"]
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
        None
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

# ---- shape queries (pure, so they can carry examples) ------------------
fn node_count(n :: Node) -> Int
  examples {
    node_count(AgentNode({ name: "a", mode: Build, task_prefix: "" })) => 1,
    node_count(SequenceNode([])) => 0,
    node_count(impl_then_test()) => 2,
    node_count(impl_then_spec_then_test()) => 4
  }
{
  match n {
    AgentNode(_) => 1,
    SequenceNode(kids) => count_all(kids),
    ParallelNode(kids) => count_all(kids),
  }
}

fn count_all(kids :: List[Node]) -> Int {
  list.fold(kids, 0, fn (acc :: Int, k :: Node) -> Int {
    acc + node_count(k)
  })
}

fn agent_names(n :: Node) -> List[Str]
  examples {
    agent_names(impl_then_test()) => ["impl", "test"],
    agent_names(impl_then_spec_then_test()) => ["impl", "spec", "test", "review"],
    agent_names(SequenceNode([])) => []
  }
{
  match n {
    AgentNode(def) => [def.name],
    SequenceNode(kids) => names_all(kids),
    ParallelNode(kids) => names_all(kids),
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
    render_shape(AgentNode({ name: "solo", mode: Build, task_prefix: "" })) => "solo",
    render_shape(SequenceNode([])) => ""
  }
{
  match n {
    AgentNode(def) => def.name,
    SequenceNode(kids) => join_kids(kids, " → "),
    ParallelNode(kids) => join_kids(kids, " ∥ "),
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

