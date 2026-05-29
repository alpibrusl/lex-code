# Implements a function to sum all elements in a list of integers.
# This function is pure and uses list pattern matching for efficiency.

fn sum_list(xs :: [Int]) -> Int
  examples {
    sum_list([])      => 0,
    sum_list([1])     => 1,
    sum_list([1, 2, 3]) => 6,
    sum_list([10, -5, 0]) => 5,
  }
{
  match xs {
    []     => 0,
    (h :: t) => h + sum_list(t),
  }
}