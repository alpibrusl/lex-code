# Computes the nth Fibonacci number recursively.
# Since it uses recursion and only basic arithmetic, it is pure.
fn fibonacci(n :: Int) -> Int
  examples {
    fibonacci(0)   => 0,
    fibonacci(1)   => 1,
    fibonacci(2)   => 1,
    fibonacci(3)   => 2,
    fibonacci(4)   => 3,
    fibonacci(5)   => 5,
    fibonacci(6)   => 8,
    fibonacci(10)  => 55,
  }
{
  if n < 0 {
    error "Fibonacci is defined only for non-negative integers."
  }
  else if n == 0 {
    0
  }
  else if n == 1 {
    1
  }
  else {
    fibonacci(n - 1) + fibonacci(n - 2)
  }
}
