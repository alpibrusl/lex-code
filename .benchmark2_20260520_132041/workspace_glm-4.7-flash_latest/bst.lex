# Binary search tree implementation
# Tree type: Leaf represents empty node, Node represents non-empty with left and right subtrees
type Tree = Leaf | Node(Int, Tree, Tree)

# Insert a value into the BST, returning a new tree
fn insert(t :: Tree, n :: Int) -> Tree
  examples {
    insert(Leaf, 5)      => Node(5, Leaf, Leaf),
    insert(Node(5, Leaf, Leaf), 3) => Node(5, Node(3, Leaf, Leaf), Leaf),
    insert(Node(5, Leaf, Leaf), 7) => Node(5, Leaf, Node(7, Leaf, Leaf)),
    insert(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)), 5) => Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)),
    insert(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)), 4) => Node(5, Node(3, Node(4, Leaf, Leaf), Leaf), Node(7, Leaf, Leaf)),
  }
{ match t {
  Leaf       => Node(n, Leaf, Leaf),
  Node(val, left, right) => if n <= val {
    Node(val, insert(left, n), right)
  } else {
    Node(val, left, insert(right, n))
  }
}}

# Check if a value exists in the BST
fn contains(t :: Tree, n :: Int) -> Bool
  examples {
    contains(Leaf, 5)       => false,
    contains(Node(5, Leaf, Leaf), 5) => true,
    contains(Node(5, Leaf, Leaf), 3) => false,
    contains(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)), 4) => true,
    contains(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)), 8) => false,
  }
{ match t {
  Leaf        => false,
  Node(val, left, right) => if n == val {
    true
  } else if n < val {
    contains(left, n)
  } else {
    contains(right, n)
  }
}}

# Convert BST to sorted list via in-order traversal
fn to_sorted_list(t :: Tree) -> List[Int]
  examples {
    to_sorted_list(Leaf)           => [],
    to_sorted_list(Node(5, Leaf, Leaf)) => [5],
    to_sorted_list(Node(3, Leaf, Node(5, Leaf, Node(7, Leaf, Leaf)))) => [3, 5, 7],
    to_sorted_list(Node(10, Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)), Node(15, Leaf, Node(20, Leaf, Leaf)))) => [3, 5, 7, 10, 15, 20],
  }
{ match t {
  Leaf         => [],
  Node(val, left, right) => list.concat(to_sorted_list(left), [val], to_sorted_list(right))
}}