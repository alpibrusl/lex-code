import "std.list" as list
import "std.str"  as str
import "std.int"  as int

type Val = VNull | VBool(Bool) | VNum(Int) | VStr(Str) | VArr(List[Val]) | VObj(List[(Str, Val)])

fn stringify(v :: Val) -> Str
  examples {
    stringify(VNull) => "null",
    stringify(VBool(true)) => "true",
    stringify(VNum(42)) => "42",
    stringify(VStr("hi")) => "\"hi\"",
    stringify(VArr([VNum(1), VNum(2)])) => "[1, 2]",
    stringify(VObj([("a", VNum(1))])) => "{\"a\": 1}",
  }
{
  match v {
    VNull         => "null",
    VBool(b)      => if b { "true" } else { "false" },
    VNum(n)       => int.to_str(n),
    VStr(s)       => str.concat("\"", str.concat(s, "\"")),
    VArr(vs)      => {
      let arr_str := list.fold(vs, "", fn (acc :: Str, v :: Val) -> Str {
        if str.is_empty(acc) { stringify(v) } else { str.concat(str.concat(acc, ", "), stringify(v)) }
      })
      str.concat("[", str.concat(arr_str, "]"))
    },
    VObj(kvs)     => {
      let obj_str := list.fold(kvs, "", fn (acc :: Str, kv :: (Str, Val)) -> Str {
        match kv {
          (k, v) => {
            let kv_str := str.concat(str.concat("\"", str.concat(k, "\": ")), stringify(v))
            if str.is_empty(acc) { kv_str } else { str.concat(str.concat(acc, ", "), kv_str) }
          }
        }
      })
      str.concat("{", str.concat(obj_str, "}"))
    },
  }
}

fn get(v :: Val, key :: Str) -> Option[Val]
  examples {
    get(VObj([("x", VNum(1))]), "x") => Some(VNum(1)),
    get(VNull, "x") => None,
  }
{
  match v {
    VObj(kvs) => {
      list.fold(kvs, None, fn (acc :: Option[Val], kv :: (Str, Val)) -> Option[Val] {
        match acc {
          Some(v) => Some(v),
          None    => match kv {
            (k, v) => if k == key { Some(v) } else { None }
          }
        }
      })
    },
    _ => None,
  }
}