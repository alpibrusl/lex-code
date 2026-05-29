import "std.list" as list

import "std.str" as str

import "std.int" as int

type Val = VNull | VBool(Bool) | VNum(Int) | VStr(Str) | VArr(List[Val]) | VObj(List[(Str, Val)])

fn stringify(v :: Val) -> Str
  examples {
    stringify(VNull) => "null",
    stringify(VBool(true)) => "true",
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
    VArr(arr) => {
      let items := list.map(arr, stringify)
      str.concat("[", str.join(items, ", "))
    },
    VObj(obj) => {
      let items := list.map(obj, fn (kv :: (Str, Val)) -> Str {
        let key := match kv {
          (k, v) => k,
        }
        let val := match kv {
          (k, v) => stringify(v),
        }
        str.concat("\"", str.concat(str.concat(key, "\": "), val))
      })
      str.concat("{", str.concat(str.join(items, ", "), "}"))
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
    VBool(b) => None,
    VNum(n) => None,
    VStr(s) => None,
    VArr(arr) => None,
    VObj(obj) => {
      list.fold(obj, None, fn (acc :: Option[Val], kv :: (Str, Val)) -> Option[Val] {
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
  }
}

