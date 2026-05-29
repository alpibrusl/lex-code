import "std.list" as list
import "std.str" as str
import "std.int" as int

# JSON-like value type
type Val =
  | VNull
  | VBool(Bool)
  | VNum(Int)
  | VStr(Str)
  | VArr(List[Val])
  | VObj(List[(Str, Val)])

# Convert a Val to its JSON string representation
fn stringify(v :: Val) -> Str
  examples {
    stringify(VNull) => "null",
    stringify(VBool(true)) => "true",
    stringify(VBool(false)) => "false",
    stringify(VNum(42)) => "42",
    stringify(VStr("hi")) => "\"hi\"",
    stringify(VArr([VNum(1), VNum(2)])) => "[1, 2]",
    stringify(VObj([("a", VNum(1))])) => "{\"a\": 1}",
  }
{
  match v {
    VNull => "null",
    VBool(b) => if b { "true" } else { "false" },
    VNum(n) => int.to_str(n),
    VStr(s) => str.concat("\"", str.concat(s, "\"")),
    VArr(items) => {
      let inner := list.map(items, stringify),
      let joined := list.fold(inner, "", fn(acc, s) {
        if str.is_empty(acc) { s } else { str.concat(acc, str.concat(", ", s)) }
      }),
      str.concat("[", str.concat(joined, "]"))
    },
    VObj(pairs) => {
      let inner := list.map(pairs, fn(kv) {
        let (k, v) := kv,
        let key_str := str.concat("\"", str.concat(k, "\"")),
        let val_str := stringify(v),
        str.concat(key_str, str.concat(": ", val_str))
      }),
      let joined := list.fold(inner, "", fn(acc, s) {
        if str.is_empty(acc) { s } else { str.concat(acc, str.concat(", ", s)) }
      }),
      str.concat("{", str.concat(joined, "}"))
    },
  }
}

# Safely access a field in a VObj by key
fn get(v :: Val, key :: Str) -> Option[Val]
  examples {
    get(VObj([("x", VNum(1))]), "x") => Some(VNum(1)),
    get(VObj([("x", VNum(1))]), "y") => None,
    get(VNull, "x") => None,
    get(VArr([VNum(1)]), "x") => None,
  }
{
  match v {
    VObj(pairs) => {
      let found := list.find(pairs, fn(kv) { let (k, _) := kv; k == key }),
      match found {
        Some(kv) => {
          let (_, v) := kv,
          Some(v)
        },
        None => None,
      }
    },
    _ => None,
  }
}