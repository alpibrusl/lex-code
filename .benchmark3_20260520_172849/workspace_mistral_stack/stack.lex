import "std.list" as list
import "std.str"  as str
import "std.int"  as int

type Op = Push(Int) | Pop | Add | Mul | Dup | Swap

fn step(stack :: List[Int], op :: Op) -> Result[List[Int], Str]
  examples {
    step([], Push(5))             => Ok([5]),
    step([3], Pop)                => Ok([]),
    step([2, 3], Add)             => Ok([5]),
    step([2, 3], Mul)             => Ok([6]),
    step([7], Dup)                => Ok([7, 7]),
    step([1, 2], Swap)            => Ok([2, 1]),
    step([], Pop)                 => Err("underflow"),
    step([1], Add)                => Err("underflow"),
    step([], Add)                 => Err("underflow"),
    step([1], Mul)                => Err("underflow"),
    step([], Mul)                 => Err("underflow"),
    step([], Dup)                 => Err("underflow"),
    step([1], Swap)               => Err("underflow"),
    step([], Swap)                => Err("underflow"),
  }
{
  match op {
    Push(n) => Ok(list.cons(n, stack)),
    Pop     => if list.is_empty(stack) { Err("underflow") } else { Ok(list.tail(stack)) },
    Add     => if list.len(stack) < 2 {
                Err("underflow")
              } else {
                let a := match list.head(stack) { Some(v) => v, None => 0 },
                let b := match list.head(list.tail(stack)) { Some(v) => v, None => 0 },
                let rest := list.tail(list.tail(stack)),
                Ok(list.cons(a + b, rest))
              },
    Mul     => if list.len(stack) < 2 {
                Err("underflow")
              } else {
                let a := match list.head(stack) { Some(v) => v, None => 0 },
                let b := match list.head(list.tail(stack)) { Some(v) => v, None => 0 },
                let rest := list.tail(list.tail(stack)),
                Ok(list.cons(a * b, rest))
              },
    Dup     => if list.is_empty(stack) {
                Err("underflow")
              } else {
                let top := match list.head(stack) { Some(v) => v, None => 0 },
                Ok(list.cons(top, stack))
              },
    Swap    => if list.len(stack) < 2 {
                Err("underflow")
              } else {
                let a := match list.head(stack) { Some(v) => v, None => 0 },
                let b := match list.head(list.tail(stack)) { Some(v) => v, None => 0 },
                let rest := list.tail(list.tail(stack)),
                Ok(list.cons(a, list.cons(b, rest)))
              },
  }
}

fn run(ops :: List[Op]) -> Result[List[Int], Str]
  examples {
    run([])                          => Ok([]),
    run([Push(1), Push(2), Add])     => Ok([3]),
    run([Push(2), Push(3), Mul])     => Ok([6]),
    run([Push(5), Dup])              => Ok([5, 5]),
    run([Push(1), Push(2), Swap])    => Ok([2, 1]),
    run([Push(1), Pop])              => Ok([]),
    run([Pop])                       => Err("underflow"),
    run([Push(1), Add])              => Err("underflow"),
    run([Push(1), Push(2), Push(3), Add, Mul]) => Ok([5]),
  }
{
  list.fold(ops, Ok([]), fn (acc :: Result[List[Int], Str], op :: Op) -> Result[List[Int], Str] {
    match acc {
      Ok(stack) => step(stack, op),
      Err(e)    => Err(e),
    }
  })
}