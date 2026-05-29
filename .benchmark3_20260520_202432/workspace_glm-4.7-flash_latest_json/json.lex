import "std.list" as list

import "std.str" as str

import "std.int" as int

type Val = VNull | VBool(Bool) | VNum(Int) | VStr(Str) | VArr(List[Val]) | VObj(List[(Str, Val)])

fn stringify(v :: Val) -> Str
  examples {
    stringify(VNull) => "null",
    stringify(VBool(true)) => "true",
    stringify(VBool(false)) => "false",
    stringify(VNum(42)) => "42",
    stringify(VStr("hi")) => "\"hi\"",
    stringify(VArr([VNum(1), VNum(2)])) => "[1, 2]",
    stringify(VObj([("a", VNum(1))])) => "{\"a\": 1}"
  }
{
  match v {
    VNull => "null",
    VBool(b) => if b {
      "true"
    } else {
      "false"
    },
    VNum(n) => int.to_str(n),
    VStr(s) => str.concat("\"", str.concat(s, "\"")),
    VArr(xs) => str.join(list.map(xs, stringify), ", "),
    VObj(kvps) => {
      let parts := list.map(kvps, fn (kv :: (Str, Val)) -> Str {
        match kv {
          (k, v) => str.concat("\"", str.concat(k, str.concat(": ", stringify(v)))),
        }
      })
      str.concat("{", str.concat(str.join(parts, ", "), "}"))
    },
  }
}

fn get(v :: Val, key :: Str) -> Option[Val]
  examples {
    get(VObj([("x", VNum(1))]), "x") => Some(VNum(1)),
    get(VNull, "x") => None
  }
{
  match v {
    VNull => None,
    VObj(kvps) => {
      list.fold(kvps, None, fn (acc :: Option[Val], kv :: (Str, Val)) -> Option[Val] {
        match acc {
          Some(v) => Some(v),
          None => match kv {
            (k, v) => if k == key {
              Some(v)
            } else {
              None
            },
          },
        }
      })
    },
    _ => None,
  }
}

