import "std.list" as list
import "std.str"  as str
import "std.int"  as int

type Op = Push(Int) | Pop | Add | Mul | Dup | Swap

fn step(stack :: List[Int], op :: Op) -> Result[List[Int], Str]
  examples {
    step([], Push(5))   => Ok([5]),
    step([1, 2], Pop)   => Ok([1]),
    step([1, 2], Add)   => Ok([3]),
    step([1, 2], Mul)   => Ok([2]),
    step([5], Dup)      => Ok([5, 5]),
    step([1, 2], Swap)  => Ok([2, 1]),
    step([1], Pop)      => Err("underflow"),
    step([1], Add)      => Err("underflow"),
    step([], Add)       => Err("underflow"),
    step([], Mul)       => Err("underflow"),
    step([], Dup)       => Err("underflow"),
    step([], Swap)      => Err("underflow"),
  }
{ match op {
  Push(n)   => Ok(list.cons(n, stack)),
  Pop       => if list.is_empty(stack) { Err("underflow") }
               else {
                 let rest := list.tail(stack)
                 Ok(rest)
               },
  Add       => if list.is_empty(stack) || list.is_empty(list.tail(stack)) { Err("underflow") }
               else {
                 let second := list.head(list.tail(stack))
                 let rest   := list.tail(list.tail(stack))
                 Ok(list.cons(second + list.head(stack), rest))
               },
  Mul       => if list.is_empty(stack) || list.is_empty(list.tail(stack)) { Err("underflow") }
               else {
                 let second := list.head(list.tail(stack))
                 let rest   := list.tail(list.tail(stack))
                 Ok(list.cons(second * list.head(stack), rest))
               },
  Dup       => if list.is_empty(stack) { Err("underflow") }
               else {
                 let top := list.head(stack)
                 Ok(list.cons(top, list.cons(top, list.tail(stack))))
               },
  Swap      => if list.is_empty(stack) || list.is_empty(list.tail(stack)) { Err("underflow") }
               else {
                 let second := list.head(list.tail(stack))
                 let top    := list.head(stack)
                 Ok(list.cons(second, list.cons(top, list.tail(list.tail(stack)))))
               },
} }

fn run(ops :: List[Op]) -> Result[List[Int], Str]
  examples {
    run([])                     => Ok([]),
    run([Push(1), Push(2)])     => Ok([2, 1]),
    run([Push(1), Add])         => Ok([1]),
    run([Push(2), Push(3), Add, Push(4), Mul]) => Ok([14]),
    run([Push(1), Pop, Pop])    => Err("underflow"),
  }
{ list.fold(ops, Ok([]), fn (acc :: Result[List[Int], Str], op :: Op) -> Result[List[Int], Str] {
  match acc {
    Ok(s) => step(s, op),
    Err(e) => Err(e),
  }
})}