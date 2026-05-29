// Pure recursive Fibonacci
fn fib(n :: Nat) -> Nat {
  match n {
    0 => 0,
    1 => 1,
    _ => fib(n - 1) + fib(n - 2),
  }
}
examples {
  fib(0) => 0,
  fib(1) => 1,
  fib(5) => 5,
  fib(10) => 55,
}