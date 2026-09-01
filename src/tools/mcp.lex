# lex-code — external tools from MCP servers
#
# Turns the tools an MCP server advertises into ordinary `t.Tool` values,
# so the agent loop dispatches them exactly as it dispatches `lex_check`.
# That sameness is the point of #27: an external tool must not be a
# privileged tool.
#
# ---- the gate ---------------------------------------------------------
#
# Two independent limits, and both are needed.
#
# `.lex/mcp.toml`'s `allow` list is the operator's: which of a server's
# tools this project will load at all. A server that advertises fifty
# tools does not get fifty tools in the prompt because it said so.
#
# `modes` is the agent-side half: which agent modes a server's tools are
# offered to, defaulting to build alone — the one mode whose permission
# spec already permits everything, so adding a tool there grants no new
# authority to a restricted agent. Loading a tool and permitting an agent
# to use it are different decisions, and collapsing them is how an
# integration becomes a hole.
#
# The issue asked for an `mcp_tool(name)` predicate in rules.lex; there is
# none, and that file says why. Short version: it is not expressible in
# lex-spec, and enforcement is still tool-list based, so `modes` is the
# gate that actually runs.
#
# ---- names ------------------------------------------------------------
#
# Remote names are prefixed `mcp__<tool>`. Two servers can both offer
# `search`, and more importantly a server could otherwise offer a tool
# called `write` or `bash` and shadow a local one in the dispatcher's
# name lookup. The prefix makes that impossible rather than unlikely.

import "std.io" as io

import "std.str" as str

import "std.list" as list

import "std.toml" as toml

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "../mcp_client" as mcp

# `modes` is the second half of the operator's decision: which agent modes
# this server's tools are offered to. Absent, it means build only —
# build's permission spec already permits everything, so that is the one
# mode where adding a tool grants no new authority to a restricted agent.
type Server = { url :: Str, allow :: List[Str], modes :: List[Str] }

type McpConfig = { servers :: List[Server] }

fn config_path() -> Str
  examples {
    config_path() => ".lex/mcp.toml"
  }
{
  ".lex/mcp.toml"
}

fn name_prefix() -> Str
  examples {
    name_prefix() => "mcp__"
  }
{
  "mcp__"
}

fn prefixed(name :: Str) -> Str
  examples {
    prefixed("search_issues") => "mcp__search_issues",
    prefixed("write") => "mcp__write"
  }
{
  str.concat(name_prefix(), name)
}

fn is_mcp_name(name :: Str) -> Bool
  examples {
    is_mcp_name("mcp__search") => true,
    is_mcp_name("write") => false,
    is_mcp_name("mcp_") => false,
    is_mcp_name("") => false
  }
{
  str.starts_with(name, name_prefix())
}

# An empty `allow` list permits nothing, not everything.
#
# The opposite reading is the tempting one — "no filter configured, so no
# filtering" — and it is how a server that adds a tool next week gets it
# into the prompt without anyone deciding. Opting in is the only default
# that cannot surprise the operator.
fn allowed(srv :: Server, name :: Str) -> Bool
  examples {
    allowed({ url: "u", allow: ["a", "b"], modes: [] }, "a") => true,
    allowed({ url: "u", allow: ["a", "b"], modes: [] }, "c") => false,
    allowed({ url: "u", allow: [], modes: [] }, "a") => false
  }
{
  list.fold(srv.allow, false, fn (acc :: Bool, a :: Str) -> Bool {
    if acc {
      true
    } else {
      a == name
    }
  })
}

fn parse_config(text :: Str) -> Result[McpConfig, Str] {
  toml.parse(text)
}

fn default_modes() -> List[Str]
  examples {
    default_modes() => ["build"]
  }
{
  ["build"]
}

fn modes_of(srv :: Server) -> List[Str] {
  if list.is_empty(srv.modes) {
    default_modes()
  } else {
    srv.modes
  }
}

fn serves_mode(srv :: Server, mode :: Str) -> Bool
  examples {
    serves_mode({ url: "u", allow: ["a"], modes: ["refactor"] }, "refactor") => true,
    serves_mode({ url: "u", allow: ["a"], modes: ["refactor"] }, "explore") => false,
    serves_mode({ url: "u", allow: ["a"], modes: [] }, "build") => true,
    serves_mode({ url: "u", allow: ["a"], modes: [] }, "refactor") => false
  }
{
  list.fold(modes_of(srv), false, fn (acc :: Bool, m :: Str) -> Bool {
    if acc {
      true
    } else {
      m == mode
    }
  })
}

# No config file is the normal case, not an error: most projects have no
# MCP servers, and `read_config` is called on every session start.
fn read_config() -> [io] Result[Option[McpConfig], Str] {
  match io.read(config_path()) {
    Err(_) => Ok(None),
    Ok(text) => if str.is_empty(str.trim(text)) {
      Ok(None)
    } else {
      match parse_config(text) {
        Err(m) => Err(str.join([config_path(), " is not valid TOML: ", m], "")),
        Ok(cfg) => Ok(Some(cfg)),
      }
    },
  }
}

# ---- adapting one remote tool ----------------------------------------
fn describe(url :: Str, rt :: mcp.RemoteTool) -> Str {
  if str.is_empty(rt.description) {
    str.join(["(MCP tool ", rt.name, " from ", url, ")"], "")
  } else {
    str.join([rt.description, "  (MCP tool from ", url, ")"], "")
  }
}

fn to_tool(url :: Str, rt :: mcp.RemoteTool) -> t.Tool {
  t.define(prefixed(rt.name), describe(url, rt), mcp.to_model_schema(prefixed(rt.name), describe(url, rt), rt.input_schema), fn (args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
    match mcp.call_tool(url, rt.name, args) {
      Err(msg) => Err(e.single("", "mcp_call_failed", msg)),
      Ok(text) => Ok(JStr(text)),
    }
  })
}

# ---- loading ----------------------------------------------------------
# A server that cannot be reached yields no tools rather than failing the
# session. The agent then simply does not have them, which is the same
# situation as not having configured the server — where refusing to start
# would make an unrelated outage into a total outage.
#
# It is not silent: the reason is returned alongside, for the caller to
# print. A tool that quietly vanishes is the failure this codebase keeps
# finding (#32, #74), so the absence is reported even though it is not
# fatal.
type LoadResult = { tools :: List[t.Tool], notes :: List[Str] }

fn empty_load() -> LoadResult {
  { tools: [], notes: [] }
}

fn load_for_mode(mode :: Str) -> [net, io] LoadResult {
  match read_config() {
    Err(msg) => { tools: [], notes: [msg] },
    Ok(None) => empty_load(),
    Ok(Some(cfg)) => list.fold(cfg.servers, empty_load(), fn (acc :: LoadResult, srv :: Server) -> [net, io] LoadResult {
      if serves_mode(srv, mode) {
        merge(acc, load_server(srv))
      } else {
        acc
      }
    }),
  }
}

fn merge(a :: LoadResult, b :: LoadResult) -> LoadResult {
  { tools: list.concat(a.tools, b.tools), notes: list.concat(a.notes, b.notes) }
}

fn load_server(srv :: Server) -> [net] LoadResult {
  if list.is_empty(srv.allow) {
    { tools: [], notes: [str.join(["mcp: ", srv.url, " has an empty allow list — no tools loaded"], "")] }
  } else {
    match mcp.list_tools(srv.url) {
      Err(msg) => { tools: [], notes: [str.concat("mcp: ", msg)] },
      Ok(remote) => picked(srv, remote),
    }
  }
}

# Names in `allow` that the server never offered are reported. A typo in
# the config otherwise looks identical to a working setup with one fewer
# tool, and the agent is the one that discovers it, mid-task.
fn picked(srv :: Server, remote :: List[mcp.RemoteTool]) -> LoadResult {
  let kept := list.filter(remote, fn (rt :: mcp.RemoteTool) -> Bool {
    allowed(srv, rt.name)
  })
  let missing := list.filter(srv.allow, fn (a :: Str) -> Bool {
    offers(remote, a) == false
  })
  { tools: list.map(kept, fn (rt :: mcp.RemoteTool) -> t.Tool {
    to_tool(srv.url, rt)
  }), notes: if list.is_empty(missing) {
    []
  } else {
    [str.join(["mcp: ", srv.url, " does not offer: ", str.join(missing, ", ")], "")]
  } }
}

fn offers(remote :: List[mcp.RemoteTool], name :: Str) -> Bool {
  list.fold(remote, false, fn (acc :: Bool, rt :: mcp.RemoteTool) -> Bool {
    if acc {
      true
    } else {
      rt.name == name
    }
  })
}

fn tool_names(tools :: List[t.Tool]) -> List[Str] {
  list.map(tools, fn (tl :: t.Tool) -> Str {
    tl.name
  })
}

