import "lex-llm/agent" as ag

import "lex-llm/message" as msg

import "lex-llm/delta" as d

import "lex-llm/provider" as prov

import "lex-llm/providers" as providers

import "lex-trail/log" as trail_log

import "std.list" as list

import "std.iter" as iter

import "std.str" as str

import "../agents/build" as build_agent

import "../agents/plan" as plan_agent

import "../agents/explore" as explore_agent

import "../agents/refactor" as refactor_agent

import "../agents/spec_agent" as spec_a

import "../agents/test_agent" as test_a

import "../agents/review" as review_a

import "../agents/bar" as bar_a

import "./persist" as persist

import "./session_events" as evs

import "../project_memory" as pmem

import "../memory/consolidate" as consolidate

type AgentMode = Build | Plan | Explore | Refactor | Spec | Test | Review | Bar

type Session = { id :: Str, mode :: AgentMode, messages :: List[msg.Message], log :: trail_log.Log, parent :: Option[Str], memory :: Str }

type TurnResult = { steps :: List[d.Step], session :: Session }

fn pick_agent(mode :: AgentMode, provider_tag :: Str) -> [env] ag.AgentLoop {
  match provider_tag {
    "mistral" => match mode {
      Build => build_agent.mistral_agent(),
      Plan => plan_agent.mistral_agent(),
      Explore => explore_agent.mistral_agent(),
      Refactor => refactor_agent.mistral_agent(),
      Spec => spec_a.mistral_agent(),
      Test => test_a.mistral_agent(),
      Review => review_a.mistral_agent(),
      Bar => bar_a.mistral_agent(),
    },
    "openai" => match mode {
      Build => build_agent.openai_agent(),
      Plan => plan_agent.openai_agent(),
      Explore => explore_agent.openai_agent(),
      Refactor => refactor_agent.openai_agent(),
      Spec => spec_a.openai_agent(),
      Test => test_a.openai_agent(),
      Review => review_a.openai_agent(),
      Bar => bar_a.openai_agent(),
    },
    "google" => match mode {
      Build => build_agent.google_agent(),
      Plan => plan_agent.google_agent(),
      Explore => explore_agent.google_agent(),
      Refactor => refactor_agent.google_agent(),
      Spec => spec_a.google_agent(),
      Test => test_a.google_agent(),
      Review => review_a.google_agent(),
      Bar => bar_a.google_agent(),
    },
    "ollama" => match mode {
      Build => build_agent.ollama_agent(),
      Plan => plan_agent.ollama_agent(),
      Explore => explore_agent.ollama_agent(),
      Refactor => refactor_agent.ollama_agent(),
      Spec => spec_a.ollama_agent(),
      Test => test_a.ollama_agent(),
      Review => review_a.ollama_agent(),
      Bar => bar_a.ollama_agent(),
    },
    "litellm" => match mode {
      Build => build_agent.litellm_agent(),
      Plan => plan_agent.litellm_agent(),
      Explore => explore_agent.litellm_agent(),
      Refactor => refactor_agent.litellm_agent(),
      Spec => spec_a.litellm_agent(),
      Test => test_a.litellm_agent(),
      Review => review_a.litellm_agent(),
      Bar => bar_a.litellm_agent(),
    },
    "vllm" => match mode {
      Build => build_agent.vllm_agent(),
      Plan => plan_agent.vllm_agent(),
      Explore => explore_agent.vllm_agent(),
      Refactor => refactor_agent.vllm_agent(),
      Spec => spec_a.vllm_agent(),
      Test => test_a.vllm_agent(),
      Review => review_a.vllm_agent(),
      Bar => bar_a.vllm_agent(),
    },
    "vertex" => match mode {
      Build => build_agent.vertex_agent(),
      Plan => plan_agent.google_agent(),
      Explore => explore_agent.google_agent(),
      Refactor => refactor_agent.google_agent(),
      Spec => spec_a.google_agent(),
      Test => test_a.google_agent(),
      Review => review_a.google_agent(),
      Bar => bar_a.google_agent(),
    },
    "opencode" => match mode {
      Build => build_agent.opencode_agent(),
      Plan => plan_agent.opencode_agent(),
      Explore => explore_agent.opencode_agent(),
      Refactor => refactor_agent.opencode_agent(),
      Spec => spec_a.opencode_agent(),
      Test => test_a.opencode_agent(),
      Review => review_a.opencode_agent(),
      Bar => bar_a.opencode_agent(),
    },
    _ => match mode {
      Build => build_agent.agent(),
      Plan => plan_agent.agent(),
      Explore => explore_agent.agent(),
      Refactor => refactor_agent.agent(),
      Spec => spec_a.agent(),
      Test => test_a.agent(),
      Review => review_a.agent(),
      Bar => bar_a.agent(),
    },
  }
}

fn new_session(id :: Str, mode :: AgentMode) -> [sql, fs_read, fs_walk, fs_write, crypto, io, random, time] Result[Session, Str] {
  new_session_with_provider(id, mode, "anthropic")
}

# Project memory is read once here rather than per turn: it changes on the
# scale of a project, not a message, and reading it at session start keeps
# `run_turn_with_provider`'s effect row unchanged. `recall_context` answers
# "" for every failure — no store yet, unreadable db — so a session never
# fails because memory was unavailable.
# Opening a session is where candidates become memory.
#
# It runs before the first `recall_context`, so a fact the previous session
# proposed is either believed or refused by the time this one reads memory —
# never half-way. And it runs on the session's own log, so the trail records
# the promotion under the session that acted on it rather than orphaned.
#
# Deliberately inline rather than in the background. The rules are mechanical
# (no model call), so this costs a few SQLite writes; and a consolidation
# racing the session's own trail writes would trade a bounded cost for an
# unbounded class of bug. A background pass only becomes worth it if
# reconciliation ever needs to ask a model, which is a different decision.
fn new_session_with_provider(id :: Str, mode :: AgentMode, provider_tag :: Str) -> [io, sql, fs_read, fs_walk, fs_write, time, crypto, random] Result[Session, Str] {
  match persist.open_ephemeral() {
    Err(e) => Err(e),
    Ok(log) => {
      let __consolidated := consolidate.run(id)
      Ok({ id: id, mode: mode, messages: [], log: log, parent: None, memory: pmem.recall_context() })
    },
  }
}

# Resume a session from its durable trail, or start one that will persist.
#
# The web client cannot be served by the registry pattern the ACP path uses:
# `net.serve_fn` hands the handler a Request and nothing else, so there is no
# value to thread between requests and nowhere to keep an in-memory map.
#
# That constraint points at the right answer rather than a workaround. #54
# already made the conversation a projection of the trail, so a session is
# whatever its log derives — reconstructing it per request is the contract,
# not a fallback for the lack of a cache. `open_persistent` puts the log at
# `.lex/sessions/<id>.db`, so a session also survives a server restart, which
# an in-memory registry never could.
#
# A new id and a known one take the same path: `session_history` on a log
# with no events derives the empty conversation, which is exactly what a new
# session's `messages` should be. There is no "does this exist" branch to get
# wrong, and a client sending an id the server has never seen gets a working
# empty session rather than an error.
fn resume_session(id :: Str, mode :: AgentMode, provider_tag :: Str) -> [io, sql, fs_read, fs_walk, fs_write, time, crypto, random] Result[Session, Str] {
  match persist.open_persistent(id) {
    Err(e) => Err(e),
    Ok(log) => {
      let __consolidated := consolidate.run(id)
      match evs.session_history(log) {
        Err(e) => Err(str.concat("session history underivable: ", e)),
        Ok(derived) => Ok({ id: id, mode: mode, messages: derived, log: log, parent: None, memory: pmem.recall_context() }),
      }
    },
  }
}

# Prepend the recalled memory summary to an agent's system prompt. Pure, so
# the examples below run at `lex check` time and CI covers the one thing that
# can silently go wrong here: an empty recall must leave the prompt untouched
# rather than trailing separators onto it.
#
# No header is added. `project_memory.summary_of` writes its own, including
# how many facts were omitted — adding a second "## PROJECT MEMORY" here
# would push that count under a duplicate heading.
fn prefix_goal(goal :: Str, ctx :: Str) -> Str
  examples {
    prefix_goal("SYSTEM", "") => "SYSTEM",
    prefix_goal("SYSTEM", "   ") => "SYSTEM",
    prefix_goal("SYSTEM", "## PROJECT MEMORY (1 fact)\n\nConventions\n- fmt: run lex fmt") => "## PROJECT MEMORY (1 fact)\n\nConventions\n- fmt: run lex fmt\n\nSYSTEM"
  }
{
  let trimmed := str.trim(ctx)
  if str.is_empty(trimmed) {
    goal
  } else {
    str.join([trimmed, "\n\n", goal], "")
  }
}

# Why `Session.memory` is a field and not a message: it is prepended to the
# agent's SYSTEM PROMPT, never to `messages`. #54's contract is that the
# model's conversation is derived from the trail, and injecting an
# out-of-band message would break exactly the property that derivation check
# exists to hold. A system prompt is agent configuration, which the trail
# never claimed to reproduce.
#
# (The comment belongs here rather than on the type: `lex fmt` cannot
# preserve comments above a `type` declaration — lex-lang#755.)
fn with_memory(agent :: ag.AgentLoop, ctx :: Str) -> ag.AgentLoop {
  { name: agent.name, goal: prefix_goal(agent.goal, ctx), model: agent.model, provider: agent.provider, tools: agent.tools, options: agent.options, permission_spec: agent.permission_spec }
}

fn run_turn(session :: Session, user_input :: Str) -> [env, net, llm, io, proc, sql, time, approval] TurnResult {
  run_turn_with_provider(session, user_input, "anthropic")
}

# The turn contract (#54): the model context is DERIVED from the session's
# trail log, not read from the in-memory cache. Sequence: append the user
# event, re-derive the history, check the cache agrees, and only then call
# the provider. Any log failure or divergence refuses the turn in-band (the
# same idiom as run_loop's "[max_steps reached]") instead of letting the
# model see a conversation the durable record cannot reproduce.
fn run_turn_with_provider(session :: Session, user_input :: Str, provider_tag :: Str) -> [env, net, llm, io, proc, sql, time, approval] TurnResult {
  match evs.record_user(session.log, user_input) {
    Err(e) => refused_turn(session, str.concat("session log append failed: ", e)),
    Ok(_) => match evs.session_history(session.log) {
      Err(e) => refused_turn(session, str.concat("session history underivable: ", e)),
      Ok(derived) => {
        let expected := list.concat(session.messages, [msg.user(user_input)])
        if evs.history_eq(derived, expected) {
          let agent := with_memory(pick_agent(session.mode, provider_tag), session.memory)
          let step_iter := ag.run_loop_traced(agent, derived, session.log, session.parent)
          let steps := iter.to_list(step_iter)
          finish_turn(session, derived, steps)
        } else {
          refused_turn(session, "cached messages diverge from the trail-derived history")
        }
      },
    },
  }
}

# Same turn-handling as run_turn_with_provider, but on_step fires as each
# Step happens rather than after the turn is over.
#
# This used to walk run_loop_traced's Iter with a callback, which only looked
# like streaming: run_loop_traced runs the whole LLM/tool loop to completion
# before it returns, wrapping an already-materialized list, so on_step fired
# in a tight burst once the blocking call came back. The comment here used to
# say so and note that real streaming "would need a callback threaded into
# lex-llm's own loop, a larger change". That change landed — ag.run_steps_streamed
# is that loop, and this now calls it.
#
# What arrives live is every Step, not only text: each Delta as it comes off
# the socket, each tool dispatch as it is made, the final message. A provider
# with no streaming half (google, vertex) still works and still emits through
# the same callback — just all at once, as before — so nothing here branches
# on whether the provider streams.
#
# run_steps_streamed returns the same List[Step] it emitted, so this must NOT
# also walk the result with on_step; finish_turn only reads it.
#
# The budget is derived the way run_loop_traced derives it internally, since
# run_steps_streamed takes it explicitly.
fn run_turn_streaming_with_provider(session :: Session, user_input :: Str, provider_tag :: Str, on_step :: (d.Step) -> [io] Unit) -> [env, net, llm, io, proc, sql, time, approval, stream] TurnResult {
  match evs.record_user(session.log, user_input) {
    Err(e) => refused_turn(session, str.concat("session log append failed: ", e)),
    Ok(_) => match evs.session_history(session.log) {
      Err(e) => refused_turn(session, str.concat("session history underivable: ", e)),
      Ok(derived) => {
        let expected := list.concat(session.messages, [msg.user(user_input)])
        if evs.history_eq(derived, expected) {
          let agent := with_memory(pick_agent(session.mode, provider_tag), session.memory)
          let budget := ag.unwrap_int(agent.options.max_steps, 20)
          let steps := ag.run_steps_streamed(agent, derived, budget, session.log, session.parent, on_step)
          finish_turn(session, derived, steps)
        } else {
          refused_turn(session, "cached messages diverge from the trail-derived history")
        }
      },
    },
  }
}

# Close a turn: record the assistant reply as a durable event and extend the
# cache. A FAILED assistant append is deliberately not patched over — the
# cache keeps the message anyway, so the next turn's derivation check finds
# the divergence and refuses loudly. Noisy failure over silent context loss.
fn finish_turn(session :: Session, derived :: List[msg.Message], steps :: List[d.Step]) -> [sql, time] TurnResult {
  let new_msgs := match find_done_msg(steps) {
    None => derived,
    Some(m) => {
      let __recorded := evs.record_assistant(session.log, m)
      list.concat(derived, [m])
    },
  }
  let updated := { id: session.id, mode: session.mode, messages: new_msgs, log: session.log, parent: None, memory: session.memory }
  { steps: steps, session: updated }
}

# A refused turn spends no provider call: one in-band StepDone explains why,
# and the session is returned unchanged so the caller can inspect or reset.
fn refused_turn(session :: Session, reason :: Str) -> TurnResult {
  { steps: [StepDone(AssistantMsg(str.join(["[refused: ", reason, "]"], ""), []))], session: session }
}

fn find_done_msg(steps :: List[d.Step]) -> Option[msg.Message] {
  match list.head(list.filter(steps, is_done)) {
    None => None,
    Some(s) => match s {
      StepDone(m) => Some(m),
      _ => None,
    },
  }
}

fn is_done(step :: d.Step) -> Bool {
  match step {
    StepDone(_) => true,
    _ => false,
  }
}

