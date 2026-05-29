# Binary search tree implementation
type Tree = Leaf | Node(Int, Tree, Tree)

# Insert a value into the BST
fn insert(t :: Tree, n :: Int) -> Tree
  examples {
    insert(Leaf, 5)       => Node(5, Leaf, Leaf),
    insert(Node(5, L, R), 3) => Node(5, Node(3, Leaf, Leaf), R),
    insert(Node(5, L, R), 7) => Node(5, L, Node(7, Leaf, Leaf)),
    insert(Node(5, Leaf, Leaf), 5) => Node(5, Leaf, Leaf),
  }
{ match t {
  Leaf => Node(n, Leaf, Leaf),
  Node(v, left, right) =>
    if n < v { Node(v, insert(left, n), right) }
    else { if n > v { Node(v, left, insert(right, n)) } else { Node(v, left, right) } },
}}

# Check if a value exists in the BST
fn contains(t :: Tree, n :: Int) -> Bool
  examples {
    contains(Leaf, 5)           => false,
    contains(Node(5, L, R), 5)   => true,
    contains(Node(5, L, R), 3)   => true,
    contains(Node(5, L, R), 7)   => true,
    contains(Node(5, L, R), 1)   => false,
  }
{ match t {
  Leaf => false,
  Node(v, left, right) =>
    if n < v { contains(left, n) }
    else { if n > v { contains(right, n) } else { true } },
}}

# In-order traversal to get sorted list
fn to_sorted_list(t :: Tree) -> List[Int]
  examples {
    to_sorted_list(Leaf)           => [],
    to_sorted_list(Node(5, Leaf, Leaf)) => [5],
    to_sorted_list(Node(5, Leaf, Node(7, Leaf, Leaf))) => [5, 7],
    to_sorted_list(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf))) => [3, 5, 7],
  }
{ match t {
  Leaf => [],
  Node(v, left, right) =>
    list.concat(to_sorted_list(left), [v] + to_sorted_list(right)),
}}