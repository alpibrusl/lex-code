fn fib(n :: Int) -> Int
  examples {
    fib(0) => 0,
    fib(1) => 1,
    fib(2) => 1,
    fib(3) => 2,
    fib(4) => 3,
    fib(5) => 5,
    fib(10) => 55,
  }
{
  if n <= 1 {
    n
  } else {
    fib(n - 1) + fib(n - 2)
  }
}
