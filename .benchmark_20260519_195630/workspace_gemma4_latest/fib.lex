# Computes the nth Fibonacci number recursively.
# NOTE: This implementation is O(2^n) and very slow for n > 35.
fn fib(n :: Int) -> Int
  examples {
    fib(0)  => 0,
    fib(1)  => 1,
    fib(2)  => 1,
    fib(3)  => 2,
    fib(5)  => 5,
    fib(10) => 55,
  }
{
  match n {
    0 => 0,
    1 => 1,
    _ => fib(n - 1) + fib(n - 2)
  }
}