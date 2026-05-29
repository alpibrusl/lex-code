import "std.list" as list
import "std.str"  as str
import "std.int"  as int

type Op = Push(Int) | Pop | Add | Mul | Dup | Swap

fn step(stack :: List[Int], op :: Op) -> Result[List[Int], Str] {
  examples {
    step([], Push(5))           => Ok([5]),
    step([5], Push(10))         => Ok([5, 10]),
    step([5, 10], Pop)          => Ok([5]),
    step([5], Pop)              => Err("underflow"),
    step([3, 5], Add)           => Ok([8]),
    step([3], Add)              => Err("underflow"),
    step([3, 5], Mul)           => Ok([15]),
    step([3], Mul)              => Err("underflow"),
    step([5], Dup)              => Ok([5, 5]),
    step([], Dup)               => Err("underflow"),
    step([3, 5], Swap)          => Ok([5, 3]),
    step([3], Swap)             => Err("underflow"),
  }
  match op {
    Push(n) => {
      list.cons(n, stack)
    }
    Pop => {
      if list.is_empty(stack) {
        Err("underflow")
      } else {
        let h := list.head(stack)
        let t := list.tail(stack)
        Ok(t)
      }
    }
    Add => {
      if list.is_empty(stack) || list.is_empty(list.tail(stack)) {
        Err("underflow")
      } else {
        let top := list.head(stack)
        let second := list.head(list.tail(stack))
        let rest := list.tail(list.tail(stack))
        Ok(list.cons(second, list.cons(top, rest)))
      }
    }
    Mul => {
      if list.is_empty(stack) || list.is_empty(list.tail(stack)) {
        Err("underflow")
      } else {
        let top := list.head(stack)
        let second := list.head(list.tail(stack))
        let rest := list.tail(list.tail(stack))
        Ok(list.cons(second, list.cons(top, rest)))
      }
    }
    Dup => {
      if list.is_empty(stack) {
        Err("underflow")
      } else {
        let h := list.head(stack)
        let t := list.tail(stack)
        Ok(list.cons(h, list.cons(h, t)))
      }
    }
    Swap => {
      if list.is_empty(stack) || list.is_empty(list.tail(stack)) {
        Err("underflow")
      } else {
        let top := list.head(stack)
        let second := list.head(list.tail(stack))
        let rest := list.tail(list.tail(stack))
        Ok(list.cons(second, list.cons(top, rest)))
      }
    }
  }
}

fn run(ops :: List[Op]) -> Result[List[Int], Str] {
  examples {
    run([])                     => Ok([]),
    run([Push(2)])              => Ok([2]),
    run([Push(1), Push(2)])     => Ok([1, 2]),
    run([Push(3), Push(4), Add]) => Ok([7]),
    run([Push(5), Pop])         => Ok([]),
    run([Push(1), Add])         => Err("underflow"),
    run([Push(2), Push(3), Mul, Push(4), Add]) => Ok([10]),
  }
  list.fold(ops, Ok([]), fn (acc :: Result[List[Int], Str], op :: Op) -> Result[List[Int], Str] {
    match acc {
      Ok(stack) => step(stack, op),
      Err(e)    => Err(e),
    }
  })
}