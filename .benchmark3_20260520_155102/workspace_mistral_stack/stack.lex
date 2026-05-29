import "std.list" as list
import "std.str"  as str
import "std.int"  as int

# Stack operations
type Op = Push(Int) | Pop | Add | Mul | Dup | Swap

# Applies one operation to the stack. Returns Err("underflow") when stack too small.
fn step(stack :: List[Int], op :: Op) -> Result[List[Int], Str]
  examples {
    step([], Push(5))          => Ok([5]),
    step([3], Pop)             => Ok([]),
    step([1, 2], Add)          => Ok([3]),
    step([2, 3], Mul)          => Ok([6]),
    step([7], Dup)             => Ok([7, 7]),
    step([1, 2], Swap)         => Ok([2, 1]),
    step([], Pop)              => Err("underflow"),
    step([1], Add)             => Err("underflow"),
    step([], Add)              => Err("underflow"),
    step([1], Mul)             => Err("underflow"),
    step([], Mul)              => Err("underflow"),
    step([], Dup)              => Err("underflow"),
    step([1], Swap)            => Err("underflow"),
    step([], Swap)             => Err("underflow"),
  }
{
  match op {
    Push(n) => Ok(list.concat([n], stack)),
    Pop     => if list.is_empty(stack) { Err("underflow") } else { Ok(list.tail(stack)) },
    Add     => if list.len(stack) < 2 { Err("underflow") } else {
      match (list.head(stack), list.head(list.tail(stack))) {
        (Some(a), Some(b)) => Ok(list.concat([a + b], list.tail(list.tail(stack)))),
        _                  => Err("underflow"),
      }
    },
    Mul     => if list.len(stack) < 2 { Err("underflow") } else {
      match (list.head(stack), list.head(list.tail(stack))) {
        (Some(a), Some(b)) => Ok(list.concat([a * b], list.tail(list.tail(stack)))),
        _                  => Err("underflow"),
      }
    },
    Dup     => if list.is_empty(stack) { Err("underflow") } else {
      match list.head(stack) {
        Some(top) => Ok(list.concat([top], stack)),
        None      => Err("underflow"),
      }
    },
    Swap    => if list.len(stack) < 2 { Err("underflow") } else {
      match (list.head(stack), list.head(list.tail(stack))) {
        (Some(a), Some(b)) => Ok(list.concat([a, b], list.tail(list.tail(stack)))),
        _                  => Err("underflow"),
      }
    },
  }
}

# Applies all ops starting from empty stack []. Returns final stack or first error.
fn run(ops :: List[Op]) -> Result[List[Int], Str]
  examples {
    run([])                          => Ok([]),
    run([Push(1), Push(2), Add])     => Ok([3]),
    run([Push(2), Push(3), Mul])     => Ok([6]),
    run([Push(5), Dup])              => Ok([5, 5]),
    run([Push(1), Push(2), Swap])    => Ok([2, 1]),
    run([Pop])                       => Err("underflow"),
    run([Push(1), Add])              => Err("underflow"),
    run([Push(1), Push(2), Push(3), Pop, Pop, Pop]) => Ok([]),
  }
{
  list.fold(ops, Ok([]), fn (acc :: Result[List[Int], Str], op :: Op) -> Result[List[Int], Str] {
    match acc {
      Ok(stack) => step(stack, op),
      Err(e)    => Err(e),
    }
  })
}