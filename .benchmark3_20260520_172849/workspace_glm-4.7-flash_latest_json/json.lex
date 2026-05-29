import "std.list" as list
import "std.str"  as str
import "std.int"  as int

type Val = VNull | VBool(Bool) | VNum(Int) | VStr(Str) | VArr(List[Val]) | VObj(List[(Str, Val)])

fn stringify(v :: Val) -> Str
  examples {
    stringify(VNull)        => "null",
    stringify(VBool(true))  => "true",
    stringify(VBool(false)) => "false",
    stringify(VNum(42))     => "42",
    stringify(VStr("hi"))   => "\"hi\"",
    stringify(VArr([VNum(1), VNum(2)])) => "[1, 2]",
    stringify(VObj([("a", VNum(1))]))   => "{\"a\": 1}",
    stringify(VObj([("x", VStr("hello")), ("y", VNum(42))])) => "{\"x\": \"hello\", \"y\": 42}",
  }
{ stringify_rec(v, false) }

fn stringify_rec(v :: Val, in_array :: Bool) -> Str {
  match v {
    VNull     => if in_array { "null" } else { "null" },
    VBool(b)  => if b { "true" } else { "false" },
    VNum(n)   => int.to_str(n),
    VStr(s)   => str.concat("\"", str.concat(s, "\"")),
    VArr(arr) => {
      if list.is_empty(arr) { "[]" }
      else {
        let first := stringify_rec(list.head(arr), true)
        let rest := stringify_arr(arr, true)
        str.concat("[", str.concat(first, str.concat(",", str.concat(rest, "]"))))
      }
    },
    VObj(obj) => {
      if list.is_empty(obj) { "{}" }
      else {
        let first := stringify_obj(list.head(obj), false)
        let rest := stringify_obj_list(list.tail(obj), false)
        str.concat("{", str.concat(first, str.concat(",", str.concat(rest, "}"))))
      }
    },
  }
}

fn stringify_arr(arr :: List[Val], in_array :: Bool) -> Str {
  if list.is_empty(arr) { "" }
  else {
    let elem := stringify_rec(list.head(arr), true)
    let elems := stringify_arr(list.tail(arr), true)
    str.concat(elem, if list.is_empty(elems) { "" } else { str.concat(",", elems) })
  }
}

fn stringify_obj(obj :: (Str, Val), in_obj :: Bool) -> Str {
  match obj {
    (k, v) => {
      let val_str := stringify_rec(v, false)
      str.concat(k, str.concat(":", str.concat(" ", val_str)))
    },
  }
}

fn stringify_obj_list(objs :: List[(Str, Val)], in_obj :: Bool) -> Str {
  if list.is_empty(objs) { "" }
  else {
    let first := stringify_obj(list.head(objs), false)
    let rest := stringify_obj_list(list.tail(objs), false)
    str.concat(first, if list.is_empty(rest) { "" } else { str.concat(",", rest) })
  }
}

fn get(v :: Val, key :: Str) -> Option[Val]
  examples {
    get(VObj([("x", VNum(1))]), "x") => Some(VNum(1)),
    get(VObj([("x", VNum(1)), ("y", VStr("a"))]), "y") => Some(VStr("a")),
    get(VObj([]), "x") => None,
    get(VNull, "x") => None,
    get(VArr([VNum(1)]), "x") => None,
  }
{ get_obj(v, key) }

fn get_obj(v :: Val, key :: Str) -> Option[Val] {
  match v {
    VObj(obj) => list.fold(obj, None, fn (acc :: Option[Val], kv :: (Str, Val)) -> Option[Val] {
      match acc {
        Some(_) => Some(_),
        None    => match kv { (k, v) => if k == key { Some(v) } else { None } },
      }
    }),
    _ => None,
  }
}