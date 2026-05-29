fn fib(n :: Int) -> Int
  examples {
    fib(0) => 0,
    fib(1) => 1,
    fib(2) => 1,
    fib(3) => 2,
    fib(4) => 3,
    fib(5) => 5,
    fib(6) => 8,
    fib(7) => 13,
    fib(8) => 21,
    fib(9) => 34,
    fib(10) => 55,
  }
{
  if n <= 1 {
    n
  } else {
    fib(n - 1) + fib(n - 2)
  }
}