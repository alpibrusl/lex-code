# Binary Search Tree implementation

type Tree = Leaf | Node(Int, Tree, Tree)

# Insert a value into the BST
fn insert(t :: Tree, n :: Int) -> Tree
  examples {
    insert(Leaf, 5) => Node(5, Leaf, Leaf),
    insert(Node(5, Leaf, Leaf), 3) => Node(5, Node(3, Leaf, Leaf), Leaf),
    insert(Node(5, Leaf, Leaf), 7) => Node(5, Leaf, Node(7, Leaf, Leaf)),
    insert(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)), 5) => Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)),
    insert(Node(5, Leaf, Leaf), 5) => Node(5, Leaf, Leaf),
  }
{
  match t {
    Leaf => Node(n, Leaf, Leaf),
    Node(x, left, right) =>
      if n < x {
        Node(x, insert(left, n), right)
      } else {
        Node(x, left, insert(right, n))
      }
  }
}

# Check if a value exists in the BST
fn contains(t :: Tree, n :: Int) -> Bool
  examples {
    contains(Leaf, 5) => false,
    contains(Node(5, Leaf, Leaf), 5) => true,
    contains(Node(5, Leaf, Leaf), 3) => false,
    contains(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)), 4) => false,
    contains(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)), 3) => true,
  }
{
  match t {
    Leaf => false,
    Node(x, left, right) =>
      if n == x {
        true
      } else if n < x {
        contains(left, n)
      } else {
        contains(right, n)
      }
  }
}

# Convert BST to sorted list using in-order traversal
fn to_sorted_list(t :: Tree) -> List[Int]
  examples {
    to_sorted_list(Leaf) => [],
    to_sorted_list(Node(5, Leaf, Leaf)) => [5],
    to_sorted_list(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf))) => [3, 5, 7],
    to_sorted_list(Node(5, Node(3, Leaf, Leaf), Node(7, Node(6, Leaf, Leaf), Leaf))) => [3, 5, 6, 7],
  }
{
  match t {
    Leaf => [],
    Node(x, left, right) => list.concat(to_sorted_list(left), list.concat([x], to_sorted_list(right)))
  }
}