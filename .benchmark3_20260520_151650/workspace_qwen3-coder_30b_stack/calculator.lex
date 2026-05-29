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
        Ok(list.tail(stack))
      },
    Add =>
      if list.len(stack) < 2 {
        Err("underflow")
      } else {
        let x := list.head(stack)
        let y := list.head(list.tail(stack))
        Ok(list.cons(x + y, list.tail(list.tail(stack))))
      },
    Mul =>
      if list.len(stack) < 2 {
        Err("underflow")
      } else {
        let x := list.head(stack)
        let y := list.head(list.tail(stack))
        Ok(list.cons(x * y, list.tail(list.tail(stack))))
      },
    Dup =>
      if list.is_empty(stack) {
        Err("underflow")
      } else {
        let x := list.head(stack)
        Ok(list.cons(x, list.cons(x, list.tail(stack))))
      },
    Swap =>
      if list.len(stack) < 2 {
        Err("underflow")
      } else {
        let x := list.head(stack)
        let y := list.head(list.tail(stack))
        Ok(list.cons(y, list.cons(x, list.tail(list.tail(stack)))))
      }
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
    run([Push(1), Add]) => Err("underflow"),
  }
{
  let result := list.fold(ops, Ok([]) :: Result[List[Int], Str], 
    fn (acc :: Result[List[Int], Str], op :: Op) -> Result[List[Int], Str] {
      match acc {
        Ok(stack) => step(stack, op),
        Err(_) => acc
      }
    }
  )
  result
}