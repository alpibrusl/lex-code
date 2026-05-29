import "std.list" as list
import "std.int"  as int

# Run-length encoding segment: count, value
type Run = Segment(Int, Int)

# Encode a list of integers into a list of Run segments
fn encode(xs :: List[Int]) -> List[Run]
  examples {
    encode([]) => [],
    encode([1]) => [Segment(1, 1)],
    encode([1, 1, 2, 2, 2, 3]) => [Segment(2, 1), Segment(3, 2), Segment(1, 3)],
  }
{
  # Helper to accumulate runs
  fn helper(xs :: List[Int], current :: Run, acc :: List[Run]) -> List[Run] {
    if list.is_empty(xs) {
      list.reverse(list.cons(current, acc))
    } else {
      let h := match list.head(xs) { Some(v) => v, None => 0 }
      let t := list.tail(xs)
      match current {
        Segment(count, value) =>
          if h == value {
            helper(t, Segment(count + 1, value), acc)
          } else {
            helper(t, Segment(1, h), list.cons(current, acc))
          },
      }
    }
  }
  
  if list.is_empty(xs) {
    []
  } else {
    let h := match list.head(xs) { Some(v) => v, None => 0 }
    let t := list.tail(xs)
    helper(t, Segment(1, h), [])
  }
}

# Decode a list of Run segments back into a list of integers
fn decode(runs :: List[Run]) -> List[Int]
  examples {
    decode([]) => [],
    decode([Segment(1, 1)]) => [1],
    decode([Segment(2, 1), Segment(3, 2)]) => [1, 1, 2, 2, 2],
  }
{
  # Helper to expand a single run
  fn expand(run :: Run, acc :: List[Int]) -> List[Int] {
    match run {
      Segment(0, _) => acc,
      Segment(count, value) => expand(Segment(count - 1, value), list.cons(value, acc)),
    }
  }
  
  # Fold over runs to expand all
  list.fold(runs, [], fn (acc :: List[Int], run :: Run) -> List[Int] {
    list.concat(expand(run, []), acc)
  })
}

# Verify that decode(encode(xs)) == xs for any xs
fn roundtrip(xs :: List[Int]) -> Bool
  examples {
    roundtrip([]) => true,
    roundtrip([1]) => true,
    roundtrip([1, 1, 2, 2, 2, 3]) => true,
  }
{
  let encoded := encode(xs)
  let decoded := decode(encoded)
  list.equal(xs, decoded, fn (a :: Int, b :: Int) -> Bool { a == b })
}