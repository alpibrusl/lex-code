import "std.list" as list
import "std.str"  as str
import "std.int"  as int

type Op = Push(Int) | Pop | Add | Mul | Dup | Swap

fn step(stack :: List[Int], op :: Op) -> Result[List[Int], Str]
  examples {
    step([], Push(5)) => Ok([5]),
    step([1, 2], Add) => Ok([3]),
    step([1, 2], Mul) => Ok([2]),
    step([1, 2], Pop) => Ok([1]),
    step([1], Dup) => Ok([1, 1]),
    step([1, 2], Swap) => Ok([2, 1]),
    step([], Add) => Err("underflow"),
    step([1], Pop) => Ok([]),
  }
{
  match op {
    Push(n) => Ok(list.cons(n, stack)),
    Pop => 
      if list.is_empty(stack) { 
        Err("underflow") 
      } else { 
        let head := list.head(stack)
        let tail := list.tail(stack)
        match head {
          Some(v) => Ok(tail),
          None => Err("underflow"),
        }
      },
    Add =>
      if list.is_empty(stack) { 
        Err("underflow") 
      } else { 
        let first := list.head(stack)
        let rest := list.tail(stack)
        match first {
          Some(a) => 
            if list.is_empty(rest) { 
              Err("underflow") 
            } else { 
              let second := list.head(rest)
              let rest2 := list.tail(rest)
              match second {
                Some(b) => Ok(list.cons(a + b, rest2)),
                None => Err("underflow"),
              }
            },
          None => Err("underflow"),
        }
      },
    Mul =>
      if list.is_empty(stack) { 
        Err("underflow") 
      } else { 
        let first := list.head(stack)
        let rest := list.tail(stack)
        match first {
          Some(a) => 
            if list.is_empty(rest) { 
              Err("underflow") 
            } else { 
              let second := list.head(rest)
              let rest2 := list.tail(rest)
              match second {
                Some(b) => Ok(list.cons(a * b, rest2)),
                None => Err("underflow"),
              }
            },
          None => Err("underflow"),
        }
      },
    Dup =>
      if list.is_empty(stack) { 
        Err("underflow") 
      } else { 
        let head := list.head(stack)
        match head {
          Some(v) => Ok(list.cons(v, stack)),
          None => Err("underflow"),
        }
      },
    Swap =>
      if list.is_empty(stack) { 
        Err("underflow") 
      } else { 
        let first := list.head(stack)
        let rest := list.tail(stack)
        match first {
          Some(a) => 
            if list.is_empty(rest) { 
              Err("underflow") 
            } else { 
              let second := list.head(rest)
              let rest2 := list.tail(rest)
              match second {
                Some(b) => Ok(list.cons(b, list.cons(a, rest2))),
                None => Err("underflow"),
              }
            },
          None => Err("underflow"),
        }
      },
  }
}

fn run(ops :: List[Op]) -> Result[List[Int], Str]
  examples {
    run([]) => Ok([]),
    run([Push(5)]) => Ok([5]),
    run([Push(1), Push(2), Add]) => Ok([3]),
    run([Push(2), Push(3), Mul]) => Ok([6]),
    run([Push(1), Push(2), Pop]) => Ok([1]),
    run([Push(1), Dup]) => Ok([1, 1]),
    run([Push(1), Push(2), Swap]) => Ok([2, 1]),
    run([Add]) => Err("underflow"),
    run([Push(1), Pop, Pop]) => Err("underflow"),
  }
{
  list.fold(ops, Ok([]), fn (acc :: Result[List[Int], Str], op :: Op) -> Result[List[Int], Str] {
    match acc {
      Ok(stack) => step(stack, op),
      Err(e) => Err(e),
    }
  })
}