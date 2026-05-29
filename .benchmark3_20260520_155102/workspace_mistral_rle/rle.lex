import "std.list" as list
import "std.int" as int

# Run-length encoding segment: count and value
type Run = Segment(Int, Int)

# Encode a list of integers into a list of Run segments
fn encode(xs :: List[Int]) -> List[Run]
  examples {
    encode([]) => [],
    encode([1]) => [Segment(1, 1)],
    encode([1, 1, 2, 2, 2, 3]) => [Segment(2, 1), Segment(3, 2), Segment(1, 3)],
    encode([5, 5, 5, 5, 5]) => [Segment(5, 5)],
    encode([1, 2, 3, 4, 5]) => [Segment(1, 1), Segment(1, 2), Segment(1, 3), Segment(1, 4), Segment(1, 5)],
  }
{
  # Helper function to encode a single run
  fn go(count :: Int, value :: Int, rest :: List[Int]) -> List[Run] {
    match list.head(rest) {
      None => [Segment(count, value)],
      Some(next) => if next == value {
        go(count + 1, value, list.tail(rest))
      } else {
        list.concat([Segment(count, value)], encode(rest))
      },
    }
  }

  match list.head(xs) {
    None => [],
    Some(value) => go(1, value, list.tail(xs)),
  }
}

# Decode a list of Run segments back into a list of integers
fn decode(runs :: List[Run]) -> List[Int]
  examples {
    decode([]) => [],
    decode([Segment(1, 1)]) => [1],
    decode([Segment(2, 1), Segment(3, 2)]) => [1, 1, 2, 2, 2],
    decode([Segment(5, 5)]) => [5, 5, 5, 5, 5],
    decode([Segment(1, 1), Segment(1, 2)]) => [1, 2],
  }
{
  # Helper function to expand a single run
  fn expand(count :: Int, value :: Int) -> List[Int] {
    if count <= 0 {
      []
    } else {
      list.concat([value], expand(count - 1, value))
    }
  }

  list.fold(runs, [], fn (acc :: List[Int], run :: Run) -> List[Int] {
    match run {
      Segment(count, value) => list.concat(acc, expand(count, value)),
    }
  })
}

# Verify that decode(encode(xs)) == xs for any list xs
fn roundtrip(xs :: List[Int]) -> Bool
  examples {
    roundtrip([]) => true,
    roundtrip([1]) => true,
    roundtrip([1, 1, 2, 2, 2, 3]) => true,
    roundtrip([5, 5, 5, 5, 5]) => true,
    roundtrip([1, 2, 3, 4, 5]) => true,
  }
{
  list.eq(xs, decode(encode(xs)))
}