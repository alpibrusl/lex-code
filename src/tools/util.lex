import "lex-schema/json_value" as jv

import "lex-schema/schema" as s

import "std.list" as list

fn field_str(args :: jv.Json, key :: Str) -> Option[Str] {
  match jv.get_field(args, key) {
    None => None,
    Some(val) => jv.as_str(val),
  }
}

fn field_str_or(args :: jv.Json, key :: Str, default :: Str) -> Str {
  match field_str(args, key) {
    None => default,
    Some(v) => v,
  }
}

fn field_int(args :: jv.Json, key :: Str) -> Option[Int] {
  match jv.get_field(args, key) {
    None => None,
    Some(val) => jv.as_int(val),
  }
}

fn field_bool(args :: jv.Json, key :: Str) -> Option[Bool] {
  match jv.get_field(args, key) {
    None => None,
    Some(val) => jv.as_bool(val),
  }
}

# Does `schema` declare `name` as a boolean field?
#
# The guard for a whole bug class: a tool whose `execute` reads a flag with
# `field_bool` while its schema declares that flag a string. The model
# follows the schema and sends `"dry_run": "true"`; `jv.as_bool` on a JStr
# returns None; the flag is silently dropped. For a preview flag that means
# the real, unpreviewed operation runs — which is how `vcs_op_push`'s
# dry_run behaved until this was checked (#28).
#
# Each affected tool calls this from an `examples {}` block on its own
# `params()`, so the schema and the reader are pinned together at
# `lex check` time rather than diverging silently.
fn declares_bool(schema :: s.ModelSchema, name :: Str) -> Bool
  examples {
    declares_bool({ title: "T", description: "", fields: [s.required_bool("flag")] }, "flag") => true,
    declares_bool({ title: "T", description: "", fields: [s.optional(s.required_bool("flag"))] }, "flag") => true,
    declares_bool({ title: "T", description: "", fields: [s.required_str("flag", [])] }, "flag") => false,
    declares_bool({ title: "T", description: "", fields: [] }, "flag") => false
  }
{
  list.fold(schema.fields, false, fn (acc :: Bool, f :: s.Field) -> Bool {
    if acc {
      true
    } else {
      if f.name == name {
        match f.kind {
          KBool => true,
          _ => false,
        }
      } else {
        false
      }
    }
  })
}

