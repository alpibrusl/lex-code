import "std.list" as list
import "std.str" as str
import "std.int" as int

type Val = VNull | VBool(Bool) | VNum(Int) | VStr(Str) | VArr(List[Val]) | VObj(List[(Str, Val])]

fn stringify(v :: Val) -> Str
  examples {
    stringify(VNull) => "null",
    stringify(VBool(true)) => "true",
    stringify(VNum(42)) => "42",
    stringify(VStr("hi")) => "\"hi\"",
    stringify(VArr([VNum(1), VNum(2)])) => "[1, 2]",
    stringify(VObj([("a", VNum(1))])) => "{\"a\": 1}",
  }
{ match v {
  VNull => "null",
  VBool(b) => if b { "true" } else { "false" },
  VNum(n) => int.to_str(n),
  VStr(s) => str.concat("\"", str.concat(s, "\"")),
  VArr(arr) => str_arr(arr),
  VObj(obj) => str_obj(obj),
} }

fn str_arr(arr :: List[Val]) -> Str {
  if list.is_empty(arr) { "" }
  else {
    let first_val := stringify(list.head(arr))
    let rest_vals := stringify_list(list.tail(arr))
    if list.is_empty(rest_vals) { first_val }
    else {
      str.concat(first_val, list.fold(rest_vals, "", fn (acc :: Str, s :: Str) -> Str {
        str.concat(acc, ", ")
      }))
    }
  }
}

fn stringify_list(xs :: List[Val]) -> List[Str] {
  list.fold(xs, [], fn (acc :: List[Str], x :: Val) -> List[Str] {
    list.cons(stringify(x), acc)
  })
}

fn str_obj(obj :: List[(Str, Val)]) -> Str {
  if list.is_empty(obj) { "" }
  else {
    let first_kv := list.head(obj)
    let first_str := str.concat(str.concat("\"", str.concat(first_kv.0, "\": "), stringify(first_kv.1)))
    let rest_strs := stringify_kvlist(list.tail(obj))
    if list.is_empty(rest_strs) { first_str }
    else {
      str.concat(first_str, list.fold(rest_strs, "", fn (acc :: Str, kv :: (Str, Str)) -> Str {
        str.concat(acc, str.concat(", ", kv.1))
      }))
    }
  }
}

fn stringify_kvlist(kvlist :: List[(Str, Val)]) -> List[(Str, Str)] {
  list.fold(kvlist, [], fn (acc :: List[(Str, Str)], kv :: (Str, Val)) -> List[(Str, Str)] {
    list.cons((kv.0, stringify(kv.1)), acc)
  })
}

fn get(v :: Val, key :: Str) -> Option[Val]
  examples {
    get(VObj([("x", VNum(1))]), "x") => Some(VNum(1)),
    get(VNull, "x") => None,
  }
{ match v {
  VNull => None,
  VBool(_) => None,
  VNum(_) => None,
  VStr(_) => None,
  VArr(_) => None,
  VObj(obj) => find_in_obj(obj, key),
} }

fn find_in_obj(obj :: List[(Str, Val)], key :: Str) -> Option[Val] {
  if list.is_empty(obj) { None }
  else {
    let kv := list.head(obj)
    if kv.0 == key { Some(kv.1) }
    else {
      find_in_obj(list.tail(obj), key)
    }
  }
}