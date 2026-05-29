
# fibonacci.lex

# Computes the nth Fibonacci number recursively.
# The function is pure and does not require explicit effect annotation.
fn fib(n :: Int) -> Int
  examples {
    fib(0) => 0,
    fib(1) => 1,
    fib(2) => 1,
    fib(3) => 2,
    fib(4) => 3,
    fib(5) => 5,
    fib(6) => 8,
    fib(10) => 55,
  }
{
  match n {
    0 => 0,
    1 => 1,
    _ => fib(n - 1) + fib(n - 2)
}
}
