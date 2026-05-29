import "std.list" as list
import "std.int"  as int

type Run = Segment(Int, Int)   # Segment(count, value)

fn encode(xs :: List[Int]) -> List[Run]
  examples {
    encode([]) => [],
    encode([1]) => [Segment(1, 1)],
    encode([1,1,2,2,2,3]) => [Segment(2, 1), Segment(3, 2), Segment(1, 3)],
  }
{
  if list.is_empty(xs) {
    []
  } else {
    let x := list.head(xs)
    let rest := list.tail(xs)
    let count := 1
    let count_rest := rest
    let advance := true
    while advance && not (list.is_empty(count_rest)) {
      if list.head(count_rest) == x {
        let count := count + 1
        let count_rest := list.tail(count_rest)
      } else {
        let advance := false
      }
    }
    let remaining := count_rest
    let result := [Segment(count, x)]
    let rest_result := encode(remaining)
    list.concat(result, rest_result)
  }
}

fn decode(runs :: List[Run]) -> List[Int]
  examples {
    decode([]) => [],
    decode([Segment(2, 1), Segment(3, 2)]) => [1, 1, 2, 2, 2],
  }
{
  if list.is_empty(runs) {
    []
  } else {
    let run := list.head(runs)
    let rest := list.tail(runs)
    let count := run.0
    let value := run.1
    let repeated := list.repeat(value, count)
    let rest_result := decode(rest)
    list.concat(repeated, rest_result)
  }
}

fn roundtrip(xs :: List[Int]) -> Bool
  examples {
    roundtrip([]) => true,
    roundtrip([1,2,3]) => true,
    roundtrip([1,1,2,2,2,3]) => true,
  }
{
  let encoded := encode(xs)
  let decoded := decode(encoded)
  xs == decoded
}