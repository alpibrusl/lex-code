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
  match xs {
    [] => [],
    [x] => [Segment(1, x)],
    _ => {
      let grouped := list.fold(
        xs,
        [],
        fn (acc :: List[Run], x :: Int) -> List[Run] {
          match acc {
            [] => [Segment(1, x)],
            [Segment(count, value), ..rest] => {
              if value == x {
                [Segment(count + 1, value), ..rest]
              } else {
                [Segment(1, x), ..acc]
              }
            }
          }
        }
      );
      list.reverse(grouped)
    }
  }
}

fn decode(runs :: List[Run]) -> List[Int]
  examples {
    decode([]) => [],
    decode([Segment(2, 1), Segment(3, 2)]) => [1, 1, 2, 2, 2],
  }
{
  list.fold(
    runs,
    [],
    fn (acc :: List[Int], run :: Run) -> List[Int] {
      match run {
        Segment(count, value) => {
          let rec := fn (n :: Int, acc :: List[Int]) -> List[Int] {
            if n == 0 {
              acc
            } else {
              if n > 0 {
                rec(n - 1, [value, ..acc])
              } else {
                acc
              }
            }
          };
          rec(count, acc)
        }
      }
    }
  )
}

fn roundtrip(xs :: List[Int]) -> Bool
  examples {
    roundtrip([]) => true,
    roundtrip([1,2,3]) => true,
    roundtrip([1,1,2,2,2,3]) => true,
  }
{
  let encoded := encode(xs);
  let decoded := decode(encoded);
  match xs {
    [] => match decoded {
      [] => true,
      _ => false,
    },
    _ => {
      let rec := fn (a :: List[Int], b :: List[Int]) -> Bool {
        match a {
          [] => match b {
            [] => true,
            _ => false,
          },
          [x, ..rest_a] => match b {
            [] => false,
            [y, ..rest_b] => {
              if x == y {
                rec(rest_a, rest_b)
              } else {
                false
              }
            }
          }
        }
      };
      rec(xs, decoded)
    }
  }
}