import "lex-schema/json_value" as jv

fn field_str(args :: jv.Json, key :: Str) -> Option[Str] {
  match jv.get_field(args, key) {
    None      => None,
    Some(val) => jv.as_str(val),
  }
}

fn field_str_or(args :: jv.Json, key :: Str, default :: Str) -> Str {
  match field_str(args, key) {
    None    => default,
    Some(v) => v,
  }
}

fn field_int(args :: jv.Json, key :: Str) -> Option[Int] {
  match jv.get_field(args, key) {
    None      => None,
    Some(val) => jv.as_int(val),
  }
}

fn field_bool(args :: jv.Json, key :: Str) -> Option[Bool] {
  match jv.get_field(args, key) {
    None      => None,
    Some(val) => jv.as_bool(val),
  }
}
