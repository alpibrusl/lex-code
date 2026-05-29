// Pure Lex function computing the nth Fibonacci number recursively
// Example usage: fib(0) => 0, fib(1) => 1, fib(5) => 5
fn fib(n :: Int) -> Int {
  examples {
    fib(0) => 0,
    fib(1) => 1,
    fib(5) => 5,
    fib(10) => 55,
  }
  if n <= 1 { n } else { fib(n - 1) + fib(n - 2) }
}
