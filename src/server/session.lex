import "lex-llm/agent"   as ag
import "lex-llm/message" as msg
import "lex-llm/delta"   as d

import "lex-trail/log"   as trail_log

import "std.list" as list
import "std.iter" as iter

import "../agents/build"   as build_agent
import "../agents/plan"    as plan_agent
import "../agents/explore" as explore_agent
import "./persist"         as persist

type AgentMode =
    Build
  | Plan
  | Explore

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

fn agent_for(mode :: AgentMode) -> ag.AgentDef {
  match mode {
    Build   => build_agent.agent(),
    Plan    => plan_agent.agent(),
    Explore => explore_agent.agent(),
  }
}

fn new_session(id :: Str, mode :: AgentMode) -> [sql] Result[Session, Str] {
  match persist.open_ephemeral() {
    Err(e) => Err(e),
    Ok(log) =>
      Ok({ id:       id,
           mode:     mode,
           messages: [],
           log:      log,
           parent:   None })
  }
}

fn new_persistent_session(id :: Str, mode :: AgentMode) -> [sql, io] Result[Session, Str] {
  match persist.open_persistent(id) {
    Err(e) => Err(e),
    Ok(log) =>
      Ok({ id:       id,
           mode:     mode,
           messages: [],
           log:      log,
           parent:   None })
  }
}

fn run_turn(session :: Session, user_input :: Str)
  -> [net, llm, io, proc, sql, time] TurnResult {
  let user_msg  := msg.user(user_input)
  let messages  := list.concat(session.messages, [user_msg])
  let agent     := agent_for(session.mode)
  let step_iter := ag.run_loop_traced(agent, messages, session.log, session.parent)
  let steps     := iter.to_list(step_iter)
  let final_msg := find_done_msg(steps)
  let new_msgs  :=
    match final_msg {
      None    => messages,
      Some(m) => list.concat(messages, [m]),
    }
  let updated := { id:       session.id,
                   mode:     session.mode,
                   messages: new_msgs,
                   log:      session.log,
                   parent:   None }
  { steps: steps, session: updated }
}

fn find_done_msg(steps :: List[d.Step]) -> Option[msg.Message] {
  match list.find(steps, is_done) {
    None    => None,
    Some(s) =>
      match s {
        d.StepDone(m) => Some(m),
        _             => None,
      }
  }
}

fn is_done(step :: d.Step) -> Bool {
  match step {
    d.StepDone(_) => true,
    _             => false,
  }
}
