# lex-code — run a multi-phase pipeline against a real task
#
# This was hardcoded to implement `list.zip` as a demo: the task string,
# the four phases, and a sequential runner written out by hand, none of
# which could be pointed at anything else (#30).
#
# The runner is gone rather than parameterised. `graph.lex` already walks
# a pipeline — that is what #26 built it for — and a second implementation
# here would be one more place for the two to disagree about what "spec
# then test" means. What is left is argument handling.
#
#   LEX_TASK      what to build (defaults to the old list.zip demo)
#   LEX_TASK_SPEC a .lex/tasks/<name>.task file — its goal becomes the
#                 task, and its criteria are evaluated when the pipeline
#                 finishes, so "done" is checked rather than asserted
#   LEX_PIPELINE  a preset name, or a spec like "build,spec,test|review"
#   LEX_PROVIDER  provider tag (default anthropic)
#
# Environment rather than argv because `lex run <file> main` passes program
# arguments only after a `--`, and this is invoked without one in the
# README and in CI.

import "../server/graph" as graph

import "../task_spec" as spec

import "lex-llm/delta" as d

import "std.str" as str

import "std.io" as io

import "std.int" as int

import "std.list" as list

import "std.env" as env

fn env_or(key :: Str, fallback :: Str) -> [env] Str {
  match env.get(key) {
    None => fallback,
    Some(v) => if str.is_empty(v) {
      fallback
    } else {
      v
    },
  }
}

# The task the demo used to hardcode. Kept as the default so a bare
# `lex run src/bootstrap/run.lex main` still does what the README says.
fn demo_task() -> Str
  examples {
    demo_task() => "Add fn zip[A, B](xs :: List[A], ys :: List[B]) -> List[(A, B)] to src/list.lex"
  }
{
  "Add fn zip[A, B](xs :: List[A], ys :: List[B]) -> List[(A, B)] to src/list.lex"
}

fn demo_pipeline() -> Str
  examples {
    demo_pipeline() => "impl_then_spec_then_test"
  }
{
  "impl_then_spec_then_test"
}

# A name resolves as a preset first, then as a spec. Both are refused
# loudly rather than falling back to the default: a pipeline that silently
# runs something other than what was asked for is a wrong answer that
# looks like a working run.
fn resolve(name :: Str) -> Result[graph.Node, Str] {
  match graph.preset(name) {
    Some(node) => Ok(node),
    None => graph.from_spec(name),
  }
}

fn main() -> [env, concurrent, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] Unit {
  let pipeline_spec := env_or("LEX_PIPELINE", demo_pipeline())
  let provider_tag := env_or("LEX_PROVIDER", "anthropic")
  match resolve(pipeline_spec) {
    Err(msg) => io.print(str.join(["[bootstrap] ", msg, "\npresets: ", str.join(graph.preset_names(), ", "), "\nor a spec like build,spec,test|review"], "")),
    Ok(pipeline) => with_task(pipeline, provider_tag),
  }
}

# A task spec supersedes LEX_TASK: its `goal` is what the agents are told,
# so the words the agents act on and the criteria they are judged against
# come from one file and cannot disagree.
fn with_task(pipeline :: graph.Node, provider_tag :: Str) -> [env, concurrent, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] Unit {
  let spec_name := env_or("LEX_TASK_SPEC", "")
  if str.is_empty(spec_name) {
    run(pipeline, env_or("LEX_TASK", demo_task()), provider_tag)
  } else {
    match spec.load(spec_name) {
      Err(msg) => io.print(str.concat("[bootstrap] ", msg)),
      Ok(ts) => {
        let __ran := run(pipeline, ts.goal, provider_tag)
        verify(ts)
      },
    }
  }
}

# The point of the whole exercise: after the agents say they are done,
# check. `is_satisfied` runs every criterion rather than stopping at the
# first failure, so one round of work can address all of them.
fn verify(ts :: spec.TaskSpec) -> [io, proc] Unit {
  let __hdr := io.print("\n[bootstrap] verifying the task spec")
  io.print(spec.render(ts, spec.is_satisfied(ts)))
}

# Each agent's own turns — text, tool calls, tool results — printed as
# they appear in `r.steps`. `bootstrap/run.lex` used to report only a
# step count per agent, which hides *why* a low-step agent did or did
# not produce anything: a fast no-op and a fast, real answer both
# looked like "done — 4 steps" (#94 was found this way).
fn print_step(step :: d.Step) -> [io] Unit {
  match step {
    StepDelta(delta) => match delta {
      TextChunk(text) => io.print(text),
      ToolCallBegin(_, name) => io.print(str.concat("\n[tool: ", str.concat(name, "]"))),
      ToolArgChunk(_, _) => (),
      FinishDelta(_) => (),
      UsageDelta(_) => (),
    },
    StepToolExec(name, _) => io.print(str.concat("[running: ", str.concat(name, "]"))),
    StepToolResult(_, ok) => if ok {
      io.print("[ok]")
    } else {
      io.print("[error]")
    },
    StepDone(_) => io.print(""),
  }
}

# The "done — N steps" line stays verbatim — scripts/eval.sh greps for
# exactly that phrase to sum step counts across a run. The per-step dump
# is additional detail, not a replacement.
fn print_node(r :: graph.NodeResult) -> [io] Unit {
  let __hdr := io.print(str.join(["\n[bootstrap] --- ", r.name, " done — ", int.to_str(list.len(r.steps)), " steps ---"], ""))
  let __steps := list.map(r.steps, print_step)
  ()
}

fn run(pipeline :: graph.Node, task :: Str, provider_tag :: Str) -> [env, concurrent, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] Unit {
  let __start := io.print(str.join(["[bootstrap] ", graph.render_shape(pipeline), "  via ", provider_tag, "\n[bootstrap] task: ", task], ""))
  let result := graph.run_graph(pipeline, task, provider_tag)
  let __each := list.map(result.results, print_node)
  ()
}

