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
      let elems := list.fold(arr, [], fn (acc :: List[Str], x :: Val) -> List[Str] {
        list.cons(stringify(x), acc)
      })
      let reversed := list.reverse(elems)
      let joined := str.join(reversed, ", ")
      str.concat("[", str.concat(joined, "]"))
    },
    VObj(obj)     => {
      let elems := list.fold(obj, [], fn (acc :: List[Str], kv :: (Str, Val)) -> List[Str] {
        match kv {
          (k, v) => list.cons(str.concat("\"", str.concat(k, "\": ")), acc)
        }
      })
      let reversed := list.reverse(elems)
      let joined := str.join(reversed, ", ")
      str.concat("{", str.concat(joined, "}"))
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
    VNull         => None,
    VBool(_)      => None,
    VNum(_)       => None,
    VStr(_)       => None,
    VArr(_)       => None,
    VObj(obj)     => {
      list.fold(obj, None, fn (acc :: Option[Val], kv :: (Str, Val)) -> Option[Val] {
        match acc {
          Some(_) => Some(match acc { Some(v) => v, None => VNull }),
          None    => match kv {
            (k, v) => if k == key { Some(v) } else { None }
          }
        }
      })
    }
  }
}