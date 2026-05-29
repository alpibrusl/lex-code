# fib computes the nth Fibonacci number recursively
fn fib(n :: Int) -> Int
  examples {
    fib(0)   => 0,
    fib(1)   => 1,
    fib(2)   => 1,
    fib(3)   => 2,
    fib(4)   => 3,
    fib(5)   => 5,
  }
{
  match n {
    0 => 0,
    1 => 1,
    _ => fib(n - 1) + fib(n - 2)
  }
}