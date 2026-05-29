# Binary search tree implementation in Lex

type Tree = Leaf | Node(Int, Tree, Tree)

# Insert a value into the tree
fn insert(t :: Tree, n :: Int) -> Tree
  examples {
    insert(Leaf, 5) => Node(5, Leaf, Leaf),
    insert(Node(3, Leaf, Leaf), 5) => Node(3, Leaf, Node(5, Leaf, Leaf)),
    insert(Node(3, Leaf, Leaf), 1) => Node(3, Node(1, Leaf, Leaf), Leaf),
  }
{
  match t {
    Leaf => Node(n, Leaf, Leaf),
    Node(v, left, right) => 
      if n < v {
        Node(v, insert(left, n), right)
      } else {
        Node(v, left, insert(right, n))
      },
  }
}

# Check if a value is contained in the tree
fn contains(t :: Tree, n :: Int) -> Bool
  examples {
    contains(Leaf, 5) => false,
    contains(Node(3, Leaf, Leaf), 3) => true,
    contains(Node(3, Leaf, Leaf), 5) => false,
    contains(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)), 3) => true,
  }
{
  match t {
    Leaf => false,
    Node(v, left, right) =>
      if n == v {
        true
      } else if n < v {
        contains(left, n)
      } else {
        contains(right, n)
      },
  }
}

# Convert tree to sorted list using in-order traversal
fn to_sorted_list(t :: Tree) -> List[Int]
  examples {
    to_sorted_list(Leaf) => [],
    to_sorted_list(Node(3, Leaf, Leaf)) => [3],
    to_sorted_list(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf))) => [3, 5, 7],
  }
{
  match t {
    Leaf => [],
    Node(v, left, right) => 
      list.concat(to_sorted_list(left), list.concat([v], to_sorted_list(right))),
  }
}