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
    Push(n) => Ok(list.concat([n], stack)),
    Pop => match stack {
      [] => Err("underflow"),
      (x :: xs) => Ok(xs),
    },
    Add => match stack {
      [] => Err("underflow"),
      (x :: []) => Err("underflow"),
      (x :: (y :: ys)) => Ok(list.concat([x + y], ys)),
    },
    Mul => match stack {
      [] => Err("underflow"),
      (x :: []) => Err("underflow"),
      (x :: (y :: ys)) => Ok(list.concat([x * y], ys)),
    },
    Dup => match stack {
      [] => Err("underflow"),
      (x :: xs) => Ok(list.concat([x, x], xs)),
    },
    Swap => match stack {
      [] => Err("underflow"),
      (x :: []) => Err("underflow"),
      (x :: (y :: ys)) => Ok(list.concat([y, x], ys)),
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
    run([Pop]) => Err("underflow"),
  }
{
  list.fold(ops, Ok([]), fn (acc :: Result[List[Int], Str], op :: Op) -> Result[List[Int], Str] {
    match acc {
      Err(e) => Err(e),
      Ok(stack) => step(stack, op),
    }
  })
}