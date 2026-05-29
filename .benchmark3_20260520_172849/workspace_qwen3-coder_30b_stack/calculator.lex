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
    step([1, 2], Dup) => Ok([1, 2, 2]),
    step([1, 2], Swap) => Ok([2, 1]),
    step([], Add) => Err("underflow"),
    step([1], Add) => Err("underflow"),
  }
{
  match op {
    Push(n) => Ok(list.cons(n, stack)),
    Pop => 
      if list.is_empty(stack) { Err("underflow") }
      else { Ok(list.tail(stack)) },
    Add =>
      if list.is_empty(stack) { Err("underflow") }
      else {
        let top := match list.head(stack) { Some(v) => v, None => 0 }
        let rest := list.tail(stack)
        if list.is_empty(rest) { Err("underflow") }
        else {
          let next := match list.head(rest) { Some(v) => v, None => 0 }
          let new_rest := list.tail(rest)
          Ok(list.cons(top + next, new_rest))
        }
      },
    Mul =>
      if list.is_empty(stack) { Err("underflow") }
      else {
        let top := match list.head(stack) { Some(v) => v, None => 0 }
        let rest := list.tail(stack)
        if list.is_empty(rest) { Err("underflow") }
        else {
          let next := match list.head(rest) { Some(v) => v, None => 0 }
          let new_rest := list.tail(rest)
          Ok(list.cons(top * next, new_rest))
        }
      },
    Dup =>
      if list.is_empty(stack) { Err("underflow") }
      else {
        let top := match list.head(stack) { Some(v) => v, None => 0 }
        Ok(list.cons(top, stack))
      },
    Swap =>
      if list.is_empty(stack) { Err("underflow") }
      else {
        let top := match list.head(stack) { Some(v) => v, None => 0 }
        let rest := list.tail(stack)
        if list.is_empty(rest) { Err("underflow") }
        else {
          let next := match list.head(rest) { Some(v) => v, None => 0 }
          let new_rest := list.tail(rest)
          Ok(list.cons(next, list.cons(top, new_rest)))
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
    run([Push(1), Push(2), Dup]) => Ok([1, 2, 2]),
    run([Push(1), Push(2), Swap]) => Ok([2, 1]),
    run([Add]) => Err("underflow"),
    run([Push(1), Add]) => Err("underflow"),
  }
{
  list.fold(ops, Ok([]), fn (acc :: Result[List[Int], Str], op :: Op) -> Result[List[Int], Str] {
    match acc {
      Err(e) => Err(e),
      Ok(stack) => step(stack, op),
    }
  })
}