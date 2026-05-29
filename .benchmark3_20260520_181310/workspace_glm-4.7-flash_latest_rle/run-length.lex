import "std.list" as list
import "std.int"  as int

type Run = Segment(Int, Int)   # Segment(count, value)

fn encode(xs :: List[Int]) -> List[Run]
  examples {
    encode([]) => [],
    encode([1,1,2,2,2,3]) => [Segment(2,1), Segment(3,2), Segment(1,3)],
    encode([5,5,5,5]) => [Segment(4,5)],
  }
{
  if list.is_empty(xs) {
    []
  } else {
    let count := 1
    let value := list.head(xs)
    let tail := list.tail(xs)
    fn encode_helper(remaining :: List[Int], count :: Int, value :: Int, acc :: List[Run]) -> List[Run] {
      if list.is_empty(remaining) {
        list.cons(Segment(count, value), acc)
      } else {
        let next := list.head(remaining)
        let rest := list.tail(remaining)
        if next == value {
          encode_helper(rest, count + 1, value, acc)
        } else {
          encode_helper(rest, 1, next, list.cons(Segment(count, value), acc))
        }
      }
    }
    encode_helper(tail, count, value, [])
  }
}

fn decode(runs :: List[Run]) -> List[Int]
  examples {
    decode([]) => [],
    decode([Segment(2,1)]) => [1,1],
    decode([Segment(2,1), Segment(3,2)]) => [1,1,2,2,2],
  }
{
  if list.is_empty(runs) {
    []
  } else {
    fn decode_helper(runs :: List[Run], acc :: List[Int]) -> List[Int] {
      if list.is_empty(runs) {
        acc
      } else {
        let run := list.head(runs)
        let rest := list.tail(runs)
        let count := match run { Segment(cnt, val) => cnt }
        let value := match run { Segment(_, val) => val }
        fn repeat(val :: Int, n :: Int, acc :: List[Int]) -> List[Int] {
          if n == 0 {
            acc
          } else {
            repeat(val, n - 1, list.cons(val, acc))
          }
        }
        decode_helper(rest, repeat(value, count, acc))
      }
    }
    decode_helper(runs, [])
  }
}

fn roundtrip(xs :: List[Int]) -> Bool
  examples {
    roundtrip([]) => true,
    roundtrip([1,1,2,2,2,3]) => true,
    roundtrip([5,5,5,5]) => true,
  }
{
  let encoded := encode(xs)
  let decoded := decode(encoded)
  decoded == xs
}