# lex-code — MCP + A2A entrypoint
#
# Exposes lex-code's coding agent as ONE `code` tool over both transports
# (A2A at /, MCP at /mcp) via lex-mcp's serve_both. The 7 modes are a strategy
# knob on one capability, so they're a `mode` param — not 7 tools:
#
#   code(task, mode = build | plan | explore | refactor | spec | test | review)
#
# The brain↔skin mapping (run_loop Steps → Skill outcome) is lex-agent-llm's
# bridge.outcome_of_steps — the same bridge lex-soft uses.
#
# Why brains are built up front: pick_agent is `[env]` (it reads provider keys),
# but a Skill handler's effect row has no `env`. So we build all 7 brains once in
# main() (where env is available) and the handler just selects one by mode and
# runs its loop (run_loop is [net, llm, io, proc] — no env). Provider/model is a
# server-launch choice (LEX_CODE_PROVIDER), not a per-call tool argument.
#
# Run:
#   LEX_CODE_PROVIDER=anthropic ANTHROPIC_API_KEY=… \
#   lex run --allow-effects env,io,time,crypto,random,sql,fs_read,fs_write,net,concurrent,llm,proc \
#       src/server/mcp_main.lex main &
#   curl -s http://localhost:7778/.well-known/agent.json
#   curl -s -X POST http://localhost:7778/mcp -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
#   curl -s -X POST http://localhost:7778/mcp -d '{"jsonrpc":"2.0","id":2,"method":"tools/call",
#       "params":{"name":"code","arguments":{"task":"add retries to fetch()","mode":"refactor"}}}'

import "std.list" as list

import "std.str" as str

import "std.io" as io

import "std.env" as env

import "std.iter" as iter

import "lex-llm/src/agent" as ag

import "lex-llm/src/message" as lmsg

import "lex-agent/src/server" as srv

import "lex-agent/src/message" as amsg

import "lex-agent/src/agent_card" as card

import "lex-spec/capability" as cap

import "lex-schema/schema" as s

import "lex-schema/json_value" as jv

import "lex-agent-llm/src/bridge" as bridge

import "lex-mcp/src/compose" as compose

import "./session" as sess

# ---- capability: one `code` tool, mode is a knob -------------------
fn code_capability() -> cap.Capability {
  cap.inbound("code", "Run a coding task with lex-code. `mode` selects the agent strategy (build|plan|explore|refactor|spec|test|review; default build).", { title: "CodeArgs", description: "A coding task for lex-code.", fields: [s.required_str("task", [StrNonEmpty]), s.optional(s.required_str("mode", []))] })
}

# ---- the 7 brains, built once under env ----------------------------
type Brains = { build :: ag.AgentDef, plan :: ag.AgentDef, explore :: ag.AgentDef, refactor :: ag.AgentDef, spec :: ag.AgentDef, test :: ag.AgentDef, review :: ag.AgentDef }

fn build_brains(tag :: Str) -> [env] Brains {
  { build: sess.pick_agent(Build, tag), plan: sess.pick_agent(Plan, tag), explore: sess.pick_agent(Explore, tag), refactor: sess.pick_agent(Refactor, tag), spec: sess.pick_agent(Spec, tag), test: sess.pick_agent(Test, tag), review: sess.pick_agent(Review, tag) }
}

fn brain_for(b :: Brains, mode :: Str) -> ag.AgentDef {
  if mode == "plan" {
    b.plan
  } else {
    if mode == "explore" {
      b.explore
    } else {
      if mode == "refactor" {
        b.refactor
      } else {
        if mode == "spec" {
          b.spec
        } else {
          if mode == "test" {
            b.test
          } else {
            if mode == "review" {
              b.review
            } else {
              b.build
            }
          }
        }
      }
    }
  }
}

# ---- read {task, mode} from the inbound message -------------------
# MCP tools/call arrives as a DataPart (the arguments object); a plain A2A call
# may use a TextPart for the task. Take the first non-empty value of each.
type Args = { task :: Str, mode :: Str }

fn pick(cur :: Str, new :: Str) -> Str {
  if str.is_empty(cur) {
    new
  } else {
    cur
  }
}

fn arg_str(j :: jv.Json, key :: Str) -> Str {
  match jv.get_field(j, key) {
    Some(JStr(sv)) => sv,
    _ => "",
  }
}

fn extract(parts :: List[amsg.Part]) -> Args {
  list.fold(parts, { task: "", mode: "" }, fn (acc :: Args, p :: amsg.Part) -> Args {
    match p {
      DataPart(j) => { task: pick(acc.task, arg_str(j, "task")), mode: pick(acc.mode, arg_str(j, "mode")) },
      TextPart(sv) => { task: pick(acc.task, sv), mode: acc.mode },
      _ => acc,
    }
  })
}

# ---- handler: select a brain by mode, run the loop, map via bridge --
fn make_handler(brains :: Brains) -> (amsg.Message) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] srv.HandlerOutcome {
  fn (m :: amsg.Message) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] srv.HandlerOutcome {
    let a := extract(m.parts)
    let brain := brain_for(brains, a.mode)
    bridge.outcome_of_steps(iter.to_list(ag.run_loop(brain, [lmsg.user(a.task)])))
  }
}

# ---- provider/model: a launch choice, not a tool argument ----------
fn provider_tag_from_env() -> [env] Str {
  match env.get("LEX_CODE_PROVIDER") {
    Some(t) => pick(t, "anthropic"),
    None => "anthropic",
  }
}

fn make_agent(brains :: Brains) -> srv.AgentDef {
  srv.make_agent_def(card.make("lex-code", "Lex-specialized coding agent — A2A + MCP. One `code` tool; `mode` selects the strategy.", "0.1.0", "http://localhost:7778", [code_capability()]), [{ capability: code_capability(), handle: make_handler(brains) }])
}

fn main() -> [env, io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Nil {
  let tag := provider_tag_from_env()
  let brains := build_brains(tag)
  let __msg1 := print_line(str.concat("lex-code listening on :7778 (A2A + MCP), provider=", tag))
  let __msg2 := print_line("AgentCard: http://localhost:7778/.well-known/agent.json   MCP: POST /mcp")
  compose.serve_both(make_agent(brains), 7778)
}

fn print_line(s :: Str) -> [io] Unit {
  io.print(s)
}

