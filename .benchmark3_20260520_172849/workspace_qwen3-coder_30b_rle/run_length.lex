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
    let h := match list.head(xs) { Some(v) => v, None => 0 }
    let t := list.tail(xs)
    let count := encode_count(t, h, 1)
    list.cons(Segment(count, h), encode_rest(t, count))
  }
}

fn encode_count(xs :: List[Int], target :: Int, acc :: Int) -> Int {
  if list.is_empty(xs) { acc }
  else {
    let h := match list.head(xs) { Some(v) => v, None => 0 }
    if h == target { encode_count(list.tail(xs), target, acc + 1) }
    else { acc }
  }
}

fn encode_rest(xs :: List[Int], skip :: Int) -> List[Run] {
  if list.is_empty(xs) { [] }
  else {
    let h := match list.head(xs) { Some(v) => v, None => 0 }
    let t := list.tail(xs)
    let count := encode_count(t, h, 1)
    list.cons(Segment(count, h), encode_rest(list.tail(xs), count))
  }
}

fn decode(runs :: List[Run]) -> List[Int]
  examples {
    decode([]) => [],
    decode([Segment(2, 1), Segment(3, 2)]) => [1, 1, 2, 2, 2],
  }
{
  if list.is_empty(runs) { [] }
  else {
    let h := match list.head(runs) { Some(v) => v, None => Segment(0, 0) }
    let t := list.tail(runs)
    let h_decoded := decode_run(h)
    let t_decoded := decode(t)
    list.concat(h_decoded, t_decoded)
  }
}

fn decode_run(run :: Run) -> List[Int] {
  let count := match run { Segment(c, v) => c }
  let value := match run { Segment(c, v) => v }
  if count == 0 { [] }
  else { list.cons(value, decode_run(Segment(count - 1, value))) }
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
  list.len(xs) == list.len(decoded) && 
  list.fold(list.zip(xs, decoded), true, fn (acc :: Bool, pair :: (Int, Int)) -> Bool {
    match acc {
      true => match pair { (a, b) => a == b },
      false => false,
    }
  })
}