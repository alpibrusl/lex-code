import "std.list" as list

type Tree = Leaf | Node(Int, Tree, Tree)

fn insert(t :: Tree, n :: Int) -> Tree
  examples {
    insert(Leaf, 5) => Node(5, Leaf, Leaf),
    insert(Node(5, Leaf, Leaf), 3) => Node(5, Node(3, Leaf, Leaf), Leaf),
    insert(Node(5, Leaf, Leaf), 7) => Node(5, Leaf, Node(7, Leaf, Leaf)),
  }
{ match t {
  Leaf => Node(n, Leaf, Leaf),
  Node(k, left, right) => if n < k { Node(k, insert(left, n), right) } else { Node(k, left, insert(right, n)) }
} }

fn contains(t :: Tree, n :: Int) -> Bool
  examples {
    contains(Leaf, 5) => false,
    contains(Node(5, Leaf, Leaf), 5) => true,
    contains(Node(5, Leaf, Leaf), 3) => false,
  }
{ match t {
  Leaf => false,
  Node(k, left, right) => if n < k { contains(left, n) } else { if n == k { true } else { contains(right, n) } }
} }

fn to_sorted_list(t :: Tree) -> List[Int]
  examples {
    to_sorted_list(Leaf) => [],
    to_sorted_list(Node(5, Leaf, Leaf)) => [5],
    to_sorted_list(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf))) => [3, 5, 7],
  }
{ match t {
  Leaf => [],
  Node(k, left, right) => list.concat(to_sorted_list(left), list.concat([k], to_sorted_list(right)))
} }