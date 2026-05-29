# Binary Search Tree implementation

import "std.list" as list

type Tree = Leaf | Node(Int, Tree, Tree)

fn insert(t :: Tree, n :: Int) -> Tree
  examples {
    insert(Leaf, 5)       => Node(5, Leaf, Leaf),
    insert(Node(5, Leaf, Leaf), 3) => Node(5, Node(3, Leaf, Leaf), Leaf),
    insert(Node(5, Leaf, Leaf), 7) => Node(5, Leaf, Node(7, Leaf, Leaf)),
    insert(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)), 5) => Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)),
  }
{ match t {
  Leaf => Node(n, Leaf, Leaf),
  Node(v, left, right) => if n < v {
    Node(v, insert(left, n), right)
  } else if n > v {
    Node(v, left, insert(right, n))
  } else {
    t
  }
}}

fn contains(t :: Tree, n :: Int) -> Bool
  examples {
    contains(Leaf, 5)        => false,
    contains(Node(5, Leaf, Leaf), 5) => true,
    contains(Node(5, Leaf, Leaf), 3) => false,
    contains(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)), 5) => true,
    contains(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)), 4) => false,
    contains(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)), 6) => true,
  }
{ match t {
  Leaf => false,
  Node(v, left, right) => if n < v {
    contains(left, n)
  } else if n > v {
    contains(right, n)
  } else {
    true
  }
}}

fn to_sorted_list(t :: Tree) -> List[Int]
  examples {
    to_sorted_list(Leaf)         => [],
    to_sorted_list(Node(5, Leaf, Leaf)) => [5],
    to_sorted_list(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf))) => [3, 5, 7],
  }
{ match t {
  Leaf => [],
  Node(v, left, right) => list.concat(to_sorted_list(left), [v], to_sorted_list(right))
}}