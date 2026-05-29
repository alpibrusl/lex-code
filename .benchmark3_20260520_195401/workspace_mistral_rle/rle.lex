import "std.list" as list
import "std.int"  as int

# Run-length encoding segment: count and value
type Run = Segment(Int, Int)

# Encode a list of integers into a list of Run segments
fn encode(xs :: List[Int]) -> List[Run]
  examples {
    encode([])                     => [],
    encode([1])                    => [Segment(1, 1)],
    encode([1, 1, 2, 2, 2, 3])     => [Segment(2, 1), Segment(3, 2), Segment(1, 3)],
    encode([5, 5, 5, 5, 5])         => [Segment(5, 5)],
    encode([1, 2, 3, 4, 5])         => [Segment(1, 1), Segment(1, 2), Segment(1, 3), Segment(1, 4), Segment(1, 5)],
  }
{
  # Helper function to encode a single run
  fn encode_run(count :: Int, value :: Int, remaining :: List[Int]) -> List[Run] {
    if list.is_empty(remaining) {
      [Segment(count, value)]
    } else {
      let next := match list.head(remaining) { Some(v) => v, None => value }
      if next == value {
        encode_run(count + 1, value, list.tail(remaining))
      } else {
        list.concat([Segment(count, value)], encode_run(1, next, list.tail(remaining)))
      }
    }
  }

  if list.is_empty(xs) {
    []
  } else {
    encode_run(1, match list.head(xs) { Some(v) => v, None => 0 }, list.tail(xs))
  }
}

# Decode a list of Run segments back into a list of integers
fn decode(runs :: List[Run]) -> List[Int]
  examples {
    decode([])                              => [],
    decode([Segment(1, 1)])                  => [1],
    decode([Segment(2, 1), Segment(3, 2)])    => [1, 1, 2, 2, 2],
    decode([Segment(5, 5)])                  => [5, 5, 5, 5, 5],
    decode([Segment(1, 1), Segment(1, 2)])    => [1, 2],
  }
{
  # Helper function to expand a single run
  fn expand_run(count :: Int, value :: Int) -> List[Int] {
    if count <= 0 {
      []
    } else {
      list.cons(value, expand_run(count - 1, value))
    }
  }

  list.fold(runs, [], fn (acc :: List[Int], run :: Run) -> List[Int] {
    match run {
      Segment(count, value) => list.concat(acc, expand_run(count, value)),
    }
  })
}

# Verify that decode(encode(xs)) == xs for any list xs
fn roundtrip(xs :: List[Int]) -> Bool
  examples {
    roundtrip([])                     => true,
    roundtrip([1])                    => true,
    roundtrip([1, 1, 2, 2, 2, 3])     => true,
    roundtrip([5, 5, 5, 5, 5])         => true,
    roundtrip([1, 2, 3, 4, 5])         => true,
  }
{
  let encoded := encode(xs)
  let decoded := decode(encoded)
  list.equal(xs, decoded)
}