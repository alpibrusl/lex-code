# lex-code — the named multi-agent pipelines
#
# These three were the whole multi-agent story: each one an arrangement of
# "run in order" and "run at once", written out by hand, so a fourth
# arrangement meant a fourth function. #26 moved those two moves into
# `graph.lex` as values; what is left here is the three names, each now a
# thin call over the shared runner.
#
# They keep their old signatures on purpose. `run_impl_then_test` is what
# the TUI calls, and the acceptance criterion for #26 is that the presets
# behave as before — so this file is the compatibility surface, not a
# second implementation.

import "lex-llm/delta" as d

import "std.list" as list

import "./graph" as graph

import "./session" as sess

type MultiResult = { impl_steps :: List[d.Step], test_steps :: List[d.Step] }

fn run_task(task :: Str, mode :: sess.AgentMode, provider_tag :: Str) -> [env, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] List[d.Step] {
  let r := graph.run_agent({ name: "worker", mode: mode, task_prefix: "" }, task, provider_tag)
  r.steps
}

fn run_parallel(task :: Str, provider_tag :: Str) -> [env, concurrent, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] MultiResult {
  as_multi(graph.run_graph(graph.impl_and_test_parallel(), task, provider_tag))
}

fn run_impl_then_test(task :: Str, provider_tag :: Str) -> [env, concurrent, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] MultiResult {
  as_multi(graph.run_graph(graph.impl_then_test(), task, provider_tag))
}

fn run_impl_then_spec_then_test(task :: Str, provider_tag :: Str) -> [env, concurrent, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] List[d.Step] {
  graph.all_steps(graph.run_graph(graph.impl_then_spec_then_test(), task, provider_tag))
}

# MultiResult names exactly two slots, which is why it could not describe
# a third pipeline and why GraphResult replaced it. Kept for the callers
# that still speak in those two.
fn as_multi(g :: graph.GraphResult) -> MultiResult {
  { impl_steps: graph.steps_for(g, "impl"), test_steps: graph.steps_for(g, "test") }
}

