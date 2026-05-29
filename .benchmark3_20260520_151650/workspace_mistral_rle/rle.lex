import "std.list" as list
import "std.int" as int

# Run-length encoding segment: (count, value)
type Run = Segment(Int, Int)

# Encode a list of integers into a list of Run segments
fn encode(xs :: List[Int]) -> List[Run]
  examples {
    encode([]) => [],
    encode([1]) => [Segment(1, 1)],
    encode([1, 1, 2, 2, 2, 3]) => [Segment(2, 1), Segment(3, 2), Segment(1, 3)],
    encode([5, 5, 5, 5, 5]) => [Segment(5, 5)],
  }
{
  match xs {
    [] => [],
    [x, ..rest] => {
      fn go(ys :: List[Int], current :: Run) -> List[Run] {
        match ys {
          [] => [current],
          [y, ..ys_rest] => {
            match current {
              Segment(count, value) => {
                if value == y {
                  go(ys_rest, Segment(count + 1, value))
                } else {
                  [current, ..go(ys_rest, Segment(1, y))]
                }
              }
            }
          },
        }
      }
      go(rest, Segment(1, x))
    },
  }
}

# Decode a list of Run segments back into a list of integers
fn decode(runs :: List[Run]) -> List[Int]
  examples {
    decode([]) => [],
    decode([Segment(2, 1), Segment(3, 2)]) => [1, 1, 2, 2, 2],
    decode([Segment(1, 5)]) => [5],
    decode([Segment(5, 5)]) => [5, 5, 5, 5, 5],
  }
{
  match runs {
    [] => [],
    [Segment(count, value), ..rest] => {
      fn expand(n :: Int, v :: Int) -> List[Int] {
        if n <= 0 {
          []
        } else {
          [v, ..expand(n - 1, v)]
        }
      }
      list.concat(expand(count, value), decode(rest))
    },
  }
}

# Verify that decode(encode(xs)) == xs for any list xs
fn roundtrip(xs :: List[Int]) -> Bool
  examples {
    roundtrip([]) => true,
    roundtrip([1]) => true,
    roundtrip([1, 1, 2, 2, 2, 3]) => true,
    roundtrip([5, 5, 5, 5, 5]) => true,
  }
{
  list.equal(xs, decode(encode(xs)))
}