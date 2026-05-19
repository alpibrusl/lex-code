import "lex-llm/agent"     as ag
import "lex-llm/message"   as msg
import "lex-llm/delta"     as d
import "lex-llm/provider"  as prov
import "lex-llm/providers" as providers

import "lex-trail/log"     as trail_log

import "std.list" as list
import "std.iter" as iter
import "std.str"  as str

import "../agents/build"       as build_agent
import "../agents/plan"        as plan_agent
import "../agents/explore"     as explore_agent
import "../agents/refactor"    as refactor_agent
import "../agents/spec_agent"  as spec_a
import "../agents/test_agent"  as test_a
import "../agents/review"      as review_a
import "./persist"             as persist

type AgentMode =
    Build
  | Plan
  | Explore
  | Refactor
  | Spec
  | Test
  | Review

type Session = {
  id       :: Str,
  mode     :: AgentMode,
  messages :: List[msg.Message],
  log      :: trail_log.Log,
  parent   :: Option[Str],
}

type TurnResult = {
  steps   :: List[d.Step],
  session :: Session,
}

fn pick_agent(mode :: AgentMode, provider_tag :: Str) -> [env] ag.AgentDef {
  match provider_tag {
    "mistral" =>
      match mode {
        Build    => build_agent.mistral_agent(),
        Plan     => plan_agent.mistral_agent(),
        Explore  => explore_agent.mistral_agent(),
        Refactor => refactor_agent.mistral_agent(),
        Spec     => spec_a.mistral_agent(),
        Test     => test_a.mistral_agent(),
        Review   => review_a.mistral_agent(),
      },
    "ollama" =>
      match mode {
        Build    => build_agent.ollama_agent(),
        Plan     => plan_agent.ollama_agent(),
        Explore  => explore_agent.ollama_agent(),
        Refactor => refactor_agent.ollama_agent(),
        Spec     => spec_a.ollama_agent(),
        Test     => test_a.ollama_agent(),
        Review   => review_a.ollama_agent(),
      },
    "vllm" =>
      match mode {
        Build    => build_agent.vllm_agent(),
        Plan     => plan_agent.vllm_agent(),
        Explore  => explore_agent.vllm_agent(),
        Refactor => refactor_agent.vllm_agent(),
        Spec     => spec_a.vllm_agent(),
        Test     => test_a.vllm_agent(),
        Review   => review_a.vllm_agent(),
      },
    _ =>
      match mode {
        Build    => build_agent.agent(),
        Plan     => plan_agent.agent(),
        Explore  => explore_agent.agent(),
        Refactor => refactor_agent.agent(),
        Spec     => spec_a.agent(),
        Test     => test_a.agent(),
        Review   => review_a.agent(),
      }
  }
}

fn new_session(id :: Str, mode :: AgentMode) -> [sql, fs_write] Result[Session, Str] {
  new_session_with_provider(id, mode, "anthropic")
}

fn new_session_with_provider(id :: Str, mode :: AgentMode, provider_tag :: Str)
  -> [sql, fs_write] Result[Session, Str] {
  match persist.open_ephemeral() {
    Err(e) => Err(e),
    Ok(log) =>
      Ok({ id: id, mode: mode, messages: [], log: log, parent: None })
  }
}

fn run_turn(session :: Session, user_input :: Str)
  -> [env, net, llm, io, proc, sql, time] TurnResult {
  run_turn_with_provider(session, user_input, "anthropic")
}

fn run_turn_with_provider(
  session      :: Session,
  user_input   :: Str,
  provider_tag :: Str
) -> [env, net, llm, io, proc, sql, time] TurnResult {
  let user_msg  := msg.user(user_input)
  let messages  := list.concat(session.messages, [user_msg])
  let agent     := pick_agent(session.mode, provider_tag)
  let step_iter := ag.run_loop_traced(agent, messages, session.log, session.parent)
  let steps     := iter.to_list(step_iter)
  let final_msg := find_done_msg(steps)
  let new_msgs  :=
    match final_msg {
      None    => messages,
      Some(m) => list.concat(messages, [m]),
    }
  let updated := { id: session.id, mode: session.mode,
                   messages: new_msgs, log: session.log, parent: None }
  { steps: steps, session: updated }
}

fn find_done_msg(steps :: List[d.Step]) -> Option[msg.Message] {
  match list.head(list.filter(steps, is_done)) {
    None    => None,
    Some(s) =>
      match s {
        d.StepDone(m) => Some(m),
        _             => None,
      }
  }
}

fn is_done(step :: d.Step) -> Bool {
  match step { d.StepDone(_) => true, _ => false }
}
