import "std.list" as list
import "std.int"  as int

type Run = Segment(Int, Int)

fn encode(xs :: List[Int]) -> List[Run]
  examples {
    encode([])         => [],
    encode([1])        => [Segment(1, 1)],
    encode([1,1,2,2,2,3]) => [Segment(2, 1), Segment(3, 2), Segment(1, 3)],
    encode([1,2,3])    => [Segment(1, 1), Segment(1, 2), Segment(1, 3)],
  }
{
  if list.is_empty(xs) { [] }
  else {
    list.fold(list.tail(xs), [Segment(1, list.head(xs))], fn (acc :: List[Run], x :: Int) -> List[Run] {
      let last_run := list.head(acc)
      match last_run {
        Segment(count, value) => if x == value {
          list.cons(Segment(count + 1, value), list.tail(acc))
        } else {
          list.cons(Segment(1, x), acc)
        }
      }
    })
  }
}

fn decode(runs :: List[Run]) -> List[Int]
  examples {
    decode([])        => [],
    decode([Segment(1,1)]) => [1],
    decode([Segment(2,1), Segment(3,2)]) => [1,1,2,2,2],
  }
{
  if list.is_empty(runs) { [] }
  else {
    list.fold(runs, [], fn (acc :: List[Int], run :: Run) -> List[Int] {
      match run {
        Segment(count, value) => 
          if count == 0 { acc }
          else {
            list.fold(list.range(1, count), acc, fn (acc2 :: List[Int], _ :: Int) -> List[Int] {
              list.cons(value, acc2)
            })
          }
      }
    })
  }
}

fn roundtrip(xs :: List[Int]) -> Bool
  examples {
    roundtrip([])         => true,
    roundtrip([1,2,3])    => true,
    roundtrip([1,1,2,2,2,3]) => true,
  }
{ list.equal(xs, decode(encode(xs))) }