import "std.list" as list

import "std.int" as int

# Run-length encoding segment: (count, value)
type Run = Segment((Int, Int))

# Helper function to encode a list starting with a current value and count
fn encode_helper(xs :: List[Int], current :: Int, count :: Int) -> List[Run] {
  if list.is_empty(xs) {
    [Segment(count, current)]
  } else {
    let h := match list.head(xs) {
      Some(v) => v,
      None => current,
    }
    let t := list.tail(xs)
    if h == current {
      encode_helper(t, current, count + 1)
    } else {
      list.cons(Segment(count, current), encode_helper(t, h, 1))
    }
  }
}

# Helper function to expand a single Run into a list of values
fn expand_run(run :: Run) -> List[Int] {
  match run {
    Segment(count, value) => {
      if count <= 0 {
        []
      } else {
        list.cons(value, expand_run(Segment(count - 1, value)))
      }
    },
  }
}

# Encode a list of integers into a list of Run segments
fn encode(xs :: List[Int]) -> List[Run]
  examples {
    encode([]) => [],
    encode([1]) => [Segment(1, 1)],
    encode([1, 1, 2, 2, 2, 3]) => [Segment(2, 1), Segment(3, 2), Segment(1, 3)],
    encode([5, 5, 5, 5, 5]) => [Segment(5, 5)],
    encode([1, 2, 3, 4, 5]) => [Segment(1, 1), Segment(1, 2), Segment(1, 3), Segment(1, 4), Segment(1, 5)]
  }
{
  if list.is_empty(xs) {
    []
  } else {
    let h := match list.head(xs) {
      Some(v) => v,
      None => 0,
    }
    let t := list.tail(xs)
    encode_helper(t, h, 1)
  }
}

# Decode a list of Run segments back into a list of integers
fn decode(runs :: List[Run]) -> List[Int]
  examples {
    decode([]) => [],
    decode([Segment(1, 1)]) => [1],
    decode([Segment(2, 1), Segment(3, 2)]) => [1, 1, 2, 2, 2],
    decode([Segment(5, 5)]) => [5, 5, 5, 5, 5],
    decode([Segment(1, 1), Segment(1, 2)]) => [1, 2]
  }
{
  list.fold(runs, [], fn (acc :: List[Int], run :: Run) -> List[Int] {
    list.concat(acc, expand_run(run))
  })
}

# Verify that decode(encode(xs)) == xs for any list xs
fn roundtrip(xs :: List[Int]) -> Bool
  examples {
    roundtrip([]) => true,
    roundtrip([1]) => true,
    roundtrip([1, 1, 2, 2, 2, 3]) => true,
    roundtrip([5, 5, 5, 5, 5]) => true,
    roundtrip([1, 2, 3, 4, 5]) => true
  }
{
  let encoded := encode(xs)
  let decoded := decode(encoded)
  xs == decoded
}

