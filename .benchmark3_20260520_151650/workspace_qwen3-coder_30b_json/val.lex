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
    VArr(arr)     => {
      let arr_str := list.map(arr, stringify)
      let joined := list.join(arr_str, ", ")
      str.concat("[", str.concat(joined, "]"))
    },
    VObj(obj)     => {
      let obj_str := list.map(obj, 
        fun (k, v) -> Str {
          let v_str := stringify(v)
          str.concat("\"", str.concat(str.concat(k, "\": "), v_str))
        }
      )
      let joined := list.join(obj_str, ", ")
      str.concat("{", str.concat(joined, "}"))
    }
  }
}

fn get(v :: Val, key :: Str) -> Option[Val]
  examples {
    get(VObj([("x", VNum(1))]), "x") => Some(VNum(1)),
    get(VNull, "x") => None,
  }
{
  match v {
    VObj(obj)     => {
      let found := list.find(obj, fun (k, v) -> Bool { k == key })
      match found {
        Some(pair)  => Some(pair.1),
        None        => None,
      }
    },
    _             => None,
  }
}