# Fibonacci function (pure)

fn fibonacci(n :: Int) -> Int
  examples {
    fibonacci(0)  => 0,
    fibonacci(1)  => 1,
    fibonacci(2)  => 1,
    fibonacci(3)  => 2,
    fibonacci(5)  => 5,
    fibonacci(10) => 55,
  }
{
  if n == 0 {
    0
  } else if n == 1 {
    1
  } else {
    fibonacci(n - 1) + fibonacci(n - 2)
  }
}