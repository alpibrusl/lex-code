import "../tools/index" as tools

import "lex-llm/tool" as t

import "lex-spec/spec" as sp

import "std.list" as list

import "std.io" as io

import "std.int" as int

import "std.str" as str

fn names(ts :: List[t.Tool]) -> Str {
  str.join(list.map(ts, fn (x :: t.Tool) -> Str { x.name }), ", ")
}

fn main() -> [io] Nil {
  let all := tools.dynamic_tools()
  io.print(str.concat("dynamic_tools total: ", int.to_str(list.len(all))))
  let none_loaded := [("loaded_vcs", VBool(false)), ("loaded_spec", VBool(false)), ("loaded_store", VBool(false))]
  let vis0 := t.filter_available(all, none_loaded)
  io.print(str.concat("visible (nothing loaded): ", int.to_str(list.len(vis0))))
  io.print(str.concat("  -> ", names(vis0)))
  let vcs_loaded := [("loaded_vcs", VBool(true)), ("loaded_spec", VBool(false)), ("loaded_store", VBool(false))]
  let vis1 := t.filter_available(all, vcs_loaded)
  io.print(str.concat("visible (vcs loaded): ", int.to_str(list.len(vis1))))
  let all_loaded := [("loaded_vcs", VBool(true)), ("loaded_spec", VBool(true)), ("loaded_store", VBool(true))]
  let vis2 := t.filter_available(all, all_loaded)
  io.print(str.concat("visible (all loaded): ", int.to_str(list.len(vis2))))
}
