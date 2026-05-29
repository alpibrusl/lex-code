import "std.list" as list

import "std.int" as int

type Run = Segment((Int, Int))

# Segment(count, value)
fn encode_run(x :: Int, rest :: List[Int]) -> List[Run] {
  if list.is_empty(rest) {
    list.cons(Segment(1, x), [])
  } else {
    let next := list.head(rest)
    let remaining := list.tail(rest)
    if next == x {
      encode_run(next, remaining)
    } else {
      list.cons(Segment(1, x), encode_run(next, remaining))
    }
  }
}

fn encode(xs :: List[Int]) -> List[Run]
  examples {
    encode([]) => [],
    encode([1]) => [Segment(1, 1)],
    encode([1, 1, 2, 2, 2, 3]) => [Segment(2, 1), Segment(3, 2), Segment(1, 3)]
  }
{
  if list.is_empty(xs) {
    []
  } else {
    let first := list.head(xs)
    let rest := list.tail(xs)
    encode_run(first, rest)
  }
}

fn replicate(value :: Int, count :: Int) -> List[Int] {
  if count == 0 {
    []
  } else {
    list.cons(value, replicate(value, count - 1))
  }
}

fn decode_segment(seg :: Run) -> List[Int] {
  match seg {
    Segment(count, value) => replicate(value, count),
  }
}

fn decode(runs :: List[Run]) -> List[Int]
  examples {
    decode([]) => [],
    decode([Segment(2, 1), Segment(3, 2)]) => [1, 1, 2, 2, 2],
    decode([Segment(1, 5)]) => [5]
  }
{
  if list.is_empty(runs) {
    []
  } else {
    let first := list.head(runs)
    let rest := list.tail(runs)
    list.concat(decode_segment(first), decode(rest))
  }
}

fn roundtrip(xs :: List[Int]) -> Bool
  examples {
    roundtrip([]) => true,
    roundtrip([1]) => true,
    roundtrip([1, 1, 2, 2, 2, 3]) => true
  }
{
  decode(encode(xs)) == xs
}

