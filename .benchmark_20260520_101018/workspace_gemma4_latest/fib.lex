# fib.lex

// Computes the nth Fibonacci number recursively.
// F(0) = 0, F(1) = 1, F(n) = F(n-1) + F(n-2)
fn fib(n :: Int) -> Int
  examples {
    fib(0)  => 0,
    fib(1)  => 1,
    fib(2)  => 1,
    fib(3)  => 2,
    fib(5)  => 5,
    fib(10) => 55,
  }
{ if n <= 0 { 0 } else if n == 1 { 1 } else { fib(n - 1) + fib(n - 2) } }