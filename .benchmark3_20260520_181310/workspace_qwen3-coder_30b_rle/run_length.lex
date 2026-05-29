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
    let h := list.head(xs)
    let t := list.tail(xs)
    let count := list.fold(t, 1, fn (acc :: Int, x :: Int) -> Int {
      if x == h { acc + 1 } else { acc }
    })
    let remaining := list.fold(t, [], fn (acc :: List[Int], x :: Int) -> List[Int] {
      if x == h { acc } else { list.cons(x, acc) }
    })
    list.cons(Segment(count, h), encode(list.reverse(remaining)))
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
    let h := list.head(runs)
    let t := list.tail(runs)
    let count := match h { Segment(c, v) => c }
    let value := match h { Segment(c, v) => v }
    let repeated := list.fold([], count, fn (acc :: List[Int], _ :: Int) -> List[Int] {
      list.cons(value, acc)
    })
    list.concat(list.reverse(repeated), decode(t))
  }
}

fn roundtrip(xs :: List[Int]) -> Bool
  examples {
    roundtrip([]) => true,
    roundtrip([1, 2, 3]) => true,
    roundtrip([1,1,2,2,2,3]) => true,
  }
{
  decode(encode(xs)) == xs
}