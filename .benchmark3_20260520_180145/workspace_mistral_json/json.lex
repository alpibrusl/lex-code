import "std.list" as list
import "std.str" as str
import "std.int" as int

# JSON-like value type
type Val = VNull | VBool(Bool) | VNum(Int) | VStr(Str) | VArr(List[Val]) | VObj(List[(Str, Val)])

# Convert a Val to its JSON string representation
fn stringify(v :: Val) -> Str
  examples {
    stringify(VNull) => "null"
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
      str.concat("[", str.concat(str.join(list.reverse(inner), ", "), "]"))
    },
    VObj(pairs) => {
      let inner := list.fold(pairs, [], fn (acc :: List[Str], kv :: (Str, Val)) -> List[Str] {
        match kv {
          (k, v) => {
            let key_str := str.concat("\"", str.concat(k, "\""))
            let val_str := stringify(v)
            list.cons(str.concat(key_str, str.concat(": ", val_str)), acc)
          }
        }
      })
      str.concat("{", str.concat(str.join(list.reverse(inner), ", "), "}"))
    }
  }
}

# Retrieve a value from a VObj by key, or None if not found
fn get(v :: Val, key :: Str) -> Option[Val]
  examples {
    get(VObj([("x", VNum(1))]), "x") => Some(VNum(1))
  }
{
  match v {
    VObj(pairs) => {
      list.fold(pairs, None, fn (acc :: Option[Val], kv :: (Str, Val)) -> Option[Val] {
        match acc {
          Some(_) => acc,
          None => match kv { (k, v) => if k == key { Some(v) } else { None } }
        }
      })
    },
    _ => None
  }
}