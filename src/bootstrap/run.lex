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
#   LEX_PIPELINE  a preset name, or a spec like "build,spec,test|review"
#   LEX_PROVIDER  provider tag (default anthropic)
#
# Environment rather than argv because `lex run <file> main` passes program
# arguments only after a `--`, and this is invoked without one in the
# README and in CI.

import "../server/graph" as graph

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
  let task := env_or("LEX_TASK", demo_task())
  let spec := env_or("LEX_PIPELINE", demo_pipeline())
  let provider_tag := env_or("LEX_PROVIDER", "anthropic")
  match resolve(spec) {
    Err(msg) => io.print(str.join(["[bootstrap] ", msg, "\npresets: ", str.join(graph.preset_names(), ", "), "\nor a spec like build,spec,test|review"], "")),
    Ok(pipeline) => run(pipeline, task, provider_tag),
  }
}

fn run(pipeline :: graph.Node, task :: Str, provider_tag :: Str) -> [env, concurrent, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] Unit {
  let __start := io.print(str.join(["[bootstrap] ", graph.render_shape(pipeline), "  via ", provider_tag, "\n[bootstrap] task: ", task], ""))
  let result := graph.run_graph(pipeline, task, provider_tag)
  let __each := list.map(result.results, fn (r :: graph.NodeResult) -> [io] Unit {
    io.print(str.join(["[bootstrap] ", r.name, " done — ", int.to_str(list.len(r.steps)), " steps"], ""))
  })
  ()
}

