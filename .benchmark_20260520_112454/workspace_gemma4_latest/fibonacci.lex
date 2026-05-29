# Fibonacci function: calculates the nth Fibonacci number recursively
fn fibonacci(n :: Int) -> Int
  examples {
    fibonacci(0)   => 0,
    fibonacci(1)   => 1,
    fibonacci(2)   => 1,
    fibonacci(3)   => 2,
    fibonacci(5)   => 8,
    fibonacci(10)  => 55,
  }
{
  match n {
    0 => 0,
    1 => 1,
    _ => fibonacci(n - 1) + fibonacci(n - 2)
  }
}