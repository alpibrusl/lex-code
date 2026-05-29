import "std.list" as list
import "std.str"  as str
import "std.int"  as int

# Stack operations
type Op = Push(Int) | Pop | Add | Mul | Dup | Swap

# Applies one operation to the stack.
# Returns Err("underflow") when stack too small.
fn step(stack :: List[Int], op :: Op) -> Result[List[Int], Str]
  examples {
    step([], Push(5))             => Ok([5]),
    step([3], Pop)                => Ok([]),
    step([2, 3], Add)             => Ok([5]),
    step([2, 3], Mul)             => Ok([6]),
    step([1], Dup)                => Ok([1, 1]),
    step([1, 2], Swap)            => Ok([2, 1]),
    step([], Pop)                 => Err("underflow"),
    step([1], Add)                => Err("underflow"),
    step([], Dup)                 => Err("underflow"),
    step([1], Swap)               => Err("underflow"),
  }
{
  match op {
    Push(n) => Ok(list.concat(stack, [n])),
    Pop => {
      if list.is_empty(stack) {
        Err("underflow")
      } else {
        Ok(list.tail(stack))
      }
    },
    Add => {
      if list.len(stack) < 2 {
        Err("underflow")
      } else {
        let a := list.head(list.tail(stack)),
        let b := list.head(stack),
        let rest := list.tail(list.tail(stack)),
        Ok(list.concat(rest, [a + b]))
      }
    },
    Mul => {
      if list.len(stack) < 2 {
        Err("underflow")
      } else {
        let a := list.head(list.tail(stack)),
        let b := list.head(stack),
        let rest := list.tail(list.tail(stack)),
        Ok(list.concat(rest, [a * b]))
      }
    },
    Dup => {
      if list.is_empty(stack) {
        Err("underflow")
      } else {
        let top := list.head(stack),
        Ok(list.concat(stack, [top]))
      }
    },
    Swap => {
      if list.len(stack) < 2 {
        Err("underflow")
      } else {
        let a := list.head(stack),
        let b := list.head(list.tail(stack)),
        let rest := list.tail(list.tail(stack)),
        Ok(list.concat(list.concat(rest, [a]), [b]))
      }
    },
  }
}

# Applies all ops starting from empty stack [].
# Returns final stack or first error.
fn run(ops :: List[Op]) -> Result[List[Int], Str]
  examples {
    run([])                          => Ok([]),
    run([Push(1), Push(2), Add])     => Ok([3]),
    run([Push(2), Push(3), Mul])     => Ok([6]),
    run([Push(1), Dup])              => Ok([1, 1]),
    run([Push(1), Push(2), Swap])    => Ok([2, 1]),
    run([Push(1), Pop, Pop])         => Err("underflow"),
    run([Push(1), Add])              => Err("underflow"),
  }
{
  let final_stack := list.fold(Ok([]), ops, fn(acc :: Result[List[Int], Str], op :: Op) -> Result[List[Int], Str] {
    match acc {
      Ok(stack) => step(stack, op),
      Err(e)   => Err(e),
    }
  }),
  final_stack
}