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
    VArr(vs)      => 
      if list.is_empty(vs) { "[]" }
      else {
        let first := stringify(list.head(vs))
        let rest := list.fold(list.tail(vs), first, fn (acc :: Str, v :: Val) -> Str {
          str.concat(str.concat(acc, ", "), stringify(v))
        })
        str.concat("[", str.concat(rest, "]"))
      },
    VObj(kvs)     =>
      if list.is_empty(kvs) { "{}" }
      else {
        let first := match list.head(kvs) {
          (k, v) => str.concat("\"", str.concat(k, str.concat("\": ", stringify(v)))),
        }
        let rest := list.fold(list.tail(kvs), first, fn (acc :: Str, kv :: (Str, Val)) -> Str {
          match kv {
            (k, v) => str.concat(str.concat(acc, ", "), str.concat("\"", str.concat(k, str.concat("\": ", stringify(v)))))
          }
        })
        str.concat("{", str.concat(rest, "}"))
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
    VObj(kvs)     => 
      list.fold(kvs, None, fn (acc :: Option[Val], kv :: (Str, Val)) -> Option[Val] {
        match acc {
          Some(_) => acc,
          None    => 
            match kv {
              (k, v) => if k == key { Some(v) } else { None },
            }
        }
      }),
  }
}