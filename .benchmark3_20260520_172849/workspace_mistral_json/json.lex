import "std.list" as list
import "std.str"  as str
import "std.int"  as int

# JSON-like value type
type Val = VNull | VBool(bool) | VNum(Int) | VStr(Str) | VArr(List[Val]) | VObj(List[(Str, Val)])

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
    stringify(VObj([("a", VStr("b")), ("c", VBool(true))])) => "{\"a\": \"b\", \"c\": true}",
  }
{
  match v {
    VNull => "null",
    VBool(b) => if b { "true" } else { "false" },
    VNum(n) => int.to_str(n),
    VStr(s) => str.concat("\"", str.concat(s, "\"")),
    VArr(items) => {
      let inner := list.fold(items, [], fn (acc :: List[Str], item :: Val) -> List[Str] {
        list.cons(stringify(item), acc)
      })
      let joined := str.join(list.reverse(inner), ", ")
      str.concat("[", str.concat(joined, "]"))
    },
    VObj(fields) => {
      let inner := list.fold(fields, [], fn (acc :: List[Str], kv :: (Str, Val)) -> List[Str] {
        match kv {
          (k, v) => {
            let key_str := str.concat("\"", str.concat(k, "\""))
            let val_str := stringify(v)
            let entry := str.concat(key_str, str.concat(": ", val_str))
            list.cons(entry, acc)
          }
        }
      })
      let joined := str.join(list.reverse(inner), ", ")
      str.concat("{", str.concat(joined, "}"))
    },
  }
}

# Retrieve a value from a VObj by key, or None if not found
fn get(v :: Val, key :: Str) -> Option[Val]
  examples {
    get(VObj([("x", VNum(1))]), "x") => Some(VNum(1)),
    get(VObj([("x", VNum(1))]), "y") => None,
    get(VNull, "x") => None,
    get(VObj([("a", VStr("b")), ("c", VBool(true))]), "c") => Some(VBool(true)),
  }
{
  match v {
    VObj(fields) => {
      list.fold(fields, None, fn (acc :: Option[Val], kv :: (Str, Val)) -> Option[Val] {
        match acc {
          Some(_) => acc,
          None => match kv { (k, v) => if k == key { Some(v) } else { None } },
        }
      })
    },
    _ => None,
  }
}