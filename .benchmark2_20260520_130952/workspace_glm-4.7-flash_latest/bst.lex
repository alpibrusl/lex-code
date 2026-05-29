# Binary search tree implementation

type Tree = Leaf | Node(Int, Tree, Tree)

fn insert(t :: Tree, n :: Int) -> Tree
  examples {
    insert(Leaf, 5)       => Node(5, Leaf, Leaf),
    insert(Node(5, Leaf, Leaf), 3) => Node(5, Node(3, Leaf, Leaf), Leaf),
    insert(Node(5, Leaf, Leaf), 7) => Node(5, Leaf, Node(7, Leaf, Leaf)),
    insert(Node(3, Node(2, Leaf, Leaf), Node(4, Leaf, Leaf)), 3) => Node(3, Node(2, Leaf, Node(3, Leaf, Leaf)), Node(4, Leaf, Leaf)),
  }
{ match t {
  Leaf => Node(n, Leaf, Leaf),
  Node(v, left, right) => {
    if n <= v {
      Node(v, insert(left, n), right)
    } else {
      Node(v, left, insert(right, n))
    }
  }
}}

fn contains(t :: Tree, n :: Int) -> Bool
  examples {
    contains(Leaf, 5) => False,
    contains(Node(5, Leaf, Leaf), 5) => True,
    contains(Node(5, Leaf, Leaf), 3) => False,
    contains(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)), 5) => True,
    contains(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)), 4) => False,
    contains(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)), 6) => True,
  }
{ match t {
  Leaf => False,
  Node(v, left, right) => {
    if n == v {
      True
    } else if n < v {
      contains(left, n)
    } else {
      contains(right, n)
    }
  }
}}

fn to_sorted_list(t :: Tree) -> List[Int]
  examples {
    to_sorted_list(Leaf) => [],
    to_sorted_list(Node(5, Leaf, Leaf)) => [5],
    to_sorted_list(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf))) => [3, 5, 7],
    to_sorted_list(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Node(9, Leaf, Leaf)))) => [3, 5, 7, 9],
  }
{ match t {
  Leaf => [],
  Node(v, left, right) => list.concat(to_sorted_list(left), list.concat([v], to_sorted_list(right)))
}}