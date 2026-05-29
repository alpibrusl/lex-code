# Sum a list of integers

fn sum_list(nums :: List[Int]) -> Int
  examples {
    sum_list([]) => 0
    sum_list([1, 2, 3]) => 6
    sum_list([-1, 0, 1]) => 0
  }
{
  list.fold(nums, 0, fn(acc :: Int, n :: Int) { acc + n })
}

# Optional: Export for use in other modules
pub fn sum(nums :: List[Int]) -> Int {
  sum_list(nums)
}