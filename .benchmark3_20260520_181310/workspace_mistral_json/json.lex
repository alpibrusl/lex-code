import "std.list" as list
import "std.str"  as str
import "std.int"  as int

# JSON-like value type
type Val = VNull | VBool(Bool) | VNum(Int) | VStr(Str) | VArr(List[Val]) | VObj(List[(Str, Val)])

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
  }
{
  match v {
    VNull       => "null",
    VBool(b)    => if b { "true" } else { "false" },
    VNum(n)     => int.to_str(n),
    VStr(s)     => str.concat("\"", str.concat(s, "\"")),
    VArr(items) => str.concat("[", str.concat(stringify_list(items), "]")),
    VObj(pairs) => str.concat("{", str.concat(stringify_pairs(pairs), "}")),
  }
}

# Helper: stringify a list of Vals
fn stringify_list(items :: List[Val]) -> Str {
  list.fold(items, "", fn (acc :: Str, item :: Val) -> Str {
    let item_str := stringify(item)
    if str.is_empty(acc) {
      item_str
    } else {
      str.concat(acc, str.concat(", ", item_str))
    }
  })
}

# Helper: stringify a list of (Str, Val) pairs
fn stringify_pairs(pairs :: List[(Str, Val)]) -> Str {
  list.fold(pairs, "", fn (acc :: Str, pair :: (Str, Val)) -> Str {
    let key_str := str.concat("\"", str.concat(pair.0, "\""))
    let val_str := stringify(pair.1)
    let pair_str := str.concat(key_str, str.concat(": ", val_str))
    
    if str.is_empty(acc) {
      pair_str
    } else {
      str.concat(acc, str.concat(", ", pair_str))
    }
  })
}

# Get a value from a VObj by key, or None if not found
fn get(v :: Val, key :: Str) -> Option[Val]
  examples {
    get(VObj([("x", VNum(1))]), "x") => Some(VNum(1)),
    get(VObj([("x", VNum(1))]), "y") => None,
    get(VNull, "x") => None,
  }
{
  match v {
    VObj(pairs) => lookup_key(pairs, key),
    _           => None,
  }
}

# Helper: find a key in a list of (Str, Val) pairs
fn lookup_key(pairs :: List[(Str, Val)], key :: Str) -> Option[Val] {
  list.fold(pairs, None, fn (acc :: Option[Val], pair :: (Str, Val)) -> Option[Val] {
    match acc {
      Some(_) => acc,
      None    => if pair.0 == key { Some(pair.1) } else { None },
    }
  })
}