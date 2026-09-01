# lex-code — speaking MCP as a client
#
# lex-code has been an MCP *server* since `src/server/mcp_main.lex`: it
# exposes its own agents as tools to Claude Desktop and friends. It has
# never been a client, so all 44 tools are local `lex` subprocesses and
# nothing outside the machine — an issue tracker, a CI system, a package
# registry — can be reached (#27).
#
# lex-mcp is server-only too; `protocol.lex` there gives the method names
# and the wire shape, which is what this reuses. What it does not give is
# a client, so the two JSON-RPC calls a client needs are here.
#
# ---- why this is not a Provider-shaped integration --------------------
#
# A remote tool has to arrive as a plain `t.Tool`, because that is the only
# thing the agent loop dispatches. `Tool.execute` is fixed at
# `[net, io, proc]`, and a remote call needs exactly `net` — so an MCP tool
# fits the existing row without widening anything. The permission spec then
# gates it identically to a local tool, which is the property that makes
# this safe to add at all: an external tool is not a privileged tool.

import "std.http" as http

import "std.map" as map

import "std.bytes" as bytes

import "std.str" as str

import "std.list" as list

import "std.int" as int

import "lex-schema/json_value" as jv

import "lex-schema/schema" as s

# What a server told us about one of its tools. `input_schema` is raw JSON
# Schema, converted to a ModelSchema by `to_model_schema` below.
type RemoteTool = { name :: Str, description :: Str, input_schema :: jv.Json }

fn method_tools_list() -> Str
  examples {
    method_tools_list() => "tools/list"
  }
{
  "tools/list"
}

fn method_tools_call() -> Str
  examples {
    method_tools_call() => "tools/call"
  }
{
  "tools/call"
}

fn rpc_body(id :: Int, method :: Str, params :: jv.Json) -> Str
  examples {
    rpc_body(1, "tools/list", JObj([])) => "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{}}"
  }
{
  jv.stringify(JObj([("jsonrpc", JStr("2.0")), ("id", JInt(id)), ("method", JStr(method)), ("params", params)]))
}

fn post(url :: Str, body :: Str) -> [net] Result[Str, Str] {
  let hdrs := map.set(map.new(), "content-type", "application/json")
  let req := { method: "POST", url: url, headers: hdrs, body: Some(bytes.from_str(body)), timeout_ms: Some(30000) }
  match http.send(req) {
    Err(_) => Err(str.concat("could not reach the MCP server at ", url)),
    Ok(r) => if r.status >= 400 {
      Err(str.join(["MCP server at ", url, " returned HTTP ", int.to_str(r.status)], ""))
    } else {
      body_str(r.body)
    },
  }
}

fn body_str(b :: Bytes) -> Result[Str, Str] {
  match bytes.to_str(b) {
    Err(_) => Err("MCP response body was not valid UTF-8"),
    Ok(t) => Ok(t),
  }
}

# A JSON-RPC reply carries either `result` or `error`; an `error` with a
# message is the server telling us something, and swallowing it into a
# generic failure loses the only useful part.
fn rpc_result(body :: Str) -> Result[jv.Json, Str] {
  match jv.parse_into_errors(body) {
    Err(_) => Err("MCP response was not JSON"),
    Ok(j) => match jv.get_field(j, "error") {
      Some(err) => Err(str.concat("MCP error: ", error_text(err))),
      None => match jv.get_field(j, "result") {
        None => Err("MCP response had neither result nor error"),
        Some(res) => Ok(res),
      },
    },
  }
}

fn error_text(err :: jv.Json) -> Str {
  match jv.get_field(err, "message") {
    Some(JStr(m)) => m,
    _ => jv.stringify(err),
  }
}

fn str_field(j :: jv.Json, name :: Str) -> Str {
  match jv.get_field(j, name) {
    Some(JStr(v)) => v,
    _ => "",
  }
}

# ---- tools/list -------------------------------------------------------
fn list_tools(url :: Str) -> [net] Result[List[RemoteTool], Str] {
  match post(url, rpc_body(1, method_tools_list(), JObj([]))) {
    Err(m) => Err(m),
    Ok(body) => match rpc_result(body) {
      Err(m) => Err(m),
      Ok(res) => Ok(tools_of(res)),
    },
  }
}

fn tools_of(res :: jv.Json) -> List[RemoteTool] {
  match jv.get_field(res, "tools") {
    Some(JList(items)) => list.reverse(list.fold(items, [], fn (acc :: List[RemoteTool], it :: jv.Json) -> List[RemoteTool] {
      let name := str_field(it, "name")
      if str.is_empty(name) {
        acc
      } else {
        list.cons({ name: name, description: str_field(it, "description"), input_schema: schema_of(it) }, acc)
      }
    })),
    _ => [],
  }
}

# MCP spells it `inputSchema`; some servers send `input_schema`. Accepting
# both costs one branch and avoids a server whose tools all arrive with no
# arguments, which would fail at call time rather than at load time.
fn schema_of(it :: jv.Json) -> jv.Json {
  match jv.get_field(it, "inputSchema") {
    Some(sch) => sch,
    None => match jv.get_field(it, "input_schema") {
      Some(sch) => sch,
      None => JObj([]),
    },
  }
}

# ---- tools/call -------------------------------------------------------
# The result is a content array of typed parts; the text parts joined are
# what a tool returns to the model. `isError` is the server reporting that
# the tool itself failed, which is different from the transport failing and
# is surfaced as an Err so the agent sees it as a failed tool call.
fn call_tool(url :: Str, name :: Str, args :: jv.Json) -> [net] Result[Str, Str] {
  match post(url, rpc_body(2, method_tools_call(), JObj([("name", JStr(name)), ("arguments", args)]))) {
    Err(m) => Err(m),
    Ok(body) => match rpc_result(body) {
      Err(m) => Err(m),
      Ok(res) => if is_error(res) {
        Err(str.concat("tool reported failure: ", content_text(res)))
      } else {
        Ok(content_text(res))
      },
    },
  }
}

fn is_error(res :: jv.Json) -> Bool {
  match jv.get_field(res, "isError") {
    Some(JBool(b)) => b,
    _ => false,
  }
}

fn content_text(res :: jv.Json) -> Str {
  match jv.get_field(res, "content") {
    Some(JList(parts)) => str.join(list.reverse(list.fold(parts, [], fn (acc :: List[Str], p :: jv.Json) -> List[Str] {
      let t := str_field(p, "text")
      if str.is_empty(t) {
        acc
      } else {
        list.cons(t, acc)
      }
    })), "\n"),
    _ => "",
  }
}

# ---- JSON Schema -> ModelSchema ---------------------------------------
# The agent loop advertises tools to the model through `s.ModelSchema`, so
# a remote tool's JSON Schema has to be translated rather than passed
# through. The mapping is direct for every type MCP servers actually use.
fn kind_of(prop :: jv.Json) -> s.FieldKind {
  match jv.get_field(prop, "type") {
    Some(JStr("string")) => KStr([]),
    Some(JStr("integer")) => KInt([]),
    Some(JStr("number")) => KFloat([]),
    Some(JStr("boolean")) => KBool,
    Some(JStr("array")) => KArray(item_kind(prop), []),
    Some(JStr("object")) => KObject(to_model_schema("", "", prop)),
    _ => KStr([]),
  }
}

# An array with no `items` is described as an array of strings rather than
# refused. A tool whose schema is slightly under-specified should still be
# callable; the server validates the real arguments anyway.
fn item_kind(prop :: jv.Json) -> s.FieldKind {
  match jv.get_field(prop, "items") {
    None => KStr([]),
    Some(items) => kind_of(items),
  }
}

fn is_required(schema :: jv.Json, name :: Str) -> Bool {
  match jv.get_field(schema, "required") {
    Some(JList(names)) => list.fold(names, false, fn (acc :: Bool, n :: jv.Json) -> Bool {
      if acc {
        true
      } else {
        match n {
          JStr(s) => s == name,
          _ => false,
        }
      }
    }),
    _ => false,
  }
}

fn to_model_schema(title :: Str, description :: Str, schema :: jv.Json) -> s.ModelSchema {
  { title: title, description: description, fields: fields_of(schema) }
}

fn fields_of(schema :: jv.Json) -> List[s.Field] {
  match jv.get_field(schema, "properties") {
    Some(JObj(props)) => list.map(props, fn (entry :: (Str, jv.Json)) -> s.Field {
      match entry {
        (name, prop) => { name: name, required: is_required(schema, name), description: str_field(prop, "description"), kind: kind_of(prop) },
      }
    }),
    _ => [],
  }
}

