import "std.list" as list
import "std.str"  as str
import "std.int"  as int

type Op = Push(Int) | Pop | Add | Mul | Dup | Swap

fn step(stack :: List[Int], op :: Op) -> Result[List[Int], Str]
  examples {
    step([], Push(42))  => Ok([42]),
    step([1, 2], Pop)   => Ok([1]),
    step([1, 2, 3], Add) => Ok([1, 5]),
    step([2, 3], Mul)   => Ok([6]),
    step([5], Dup)      => Ok([5, 5]),
    step([1, 2], Swap)  => Ok([2, 1]),
    step([], Pop)       => Err("underflow"),
    step([1], Pop)      => Err("underflow"),
    step([], Add)       => Err("underflow"),
    step([1], Add)      => Err("underflow"),
  }
{ match op {
  Push(n)    => Ok(list.cons(n, stack)),
  Pop       => if list.is_empty(stack) { Err("underflow") }
               else { let rest := list.tail(stack); Ok(rest) },
  Add       => if list.is_empty(stack) { Err("underflow") }
               else {
                 if list.is_empty(list.tail(stack)) { Err("underflow") }
                 else {
                   let h := list.head(stack),
                       t := list.tail(stack),
                       top := list.head(t),
                       new_stack := list.cons(h + top, t);
                   Ok(new_stack)
                 }
               },
  Mul       => if list.is_empty(stack) { Err("underflow") }
               else {
                 if list.is_empty(list.tail(stack)) { Err("underflow") }
                 else {
                   let h := list.head(stack),
                       t := list.tail(stack),
                       top := list.head(t),
                       new_stack := list.cons(h * top, t);
                   Ok(new_stack)
                 }
               },
  Dup       => if list.is_empty(stack) { Err("underflow") }
               else {
                 let h := list.head(stack),
                     rest := list.tail(stack);
                 Ok(list.cons(h, list.cons(h, rest)))
               },
  Swap      => if list.is_empty(stack) { Err("underflow") }
               else {
                 if list.is_empty(list.tail(stack)) { Err("underflow") }
                 else {
                   let h := list.head(stack),
                       t := list.tail(stack),
                       top := list.head(t);
                   Ok(list.cons(top, list.cons(h, list.tail(t))))
                 }
               }
} }

fn run(ops :: List[Op]) -> Result[List[Int], Str]
  examples {
    run([])                      => Ok([]),
    run([Push(1), Push(2)])      => Ok([2, 1]),
    run([Push(3), Add, Push(4), Add]) => Ok([7]),
    run([Push(2), Mul, Push(3), Mul]) => Ok([6]),
    run([Push(5), Dup, Pop])     => Ok([5]),
    run([Push(1), Pop, Push(2), Pop]) => Ok([]),
    run([Push(1), Pop, Pop])     => Err("underflow"),
  }
{ list.fold(ops, Ok([]), fn (acc :: Result[List[Int], Str], op :: Op) -> Result[List[Int], Str] {
  match acc {
    Ok(s)  => step(s, op),
    Err(e) => Err(e)
  }
} ) }