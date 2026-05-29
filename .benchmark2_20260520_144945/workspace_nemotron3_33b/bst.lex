# Binary Search Tree implementation in Lex
type Tree = Leaf | Node(Int, Tree, Tree)

import "std.list" as list

fn insert(t :: Tree, n :: Int) -> Tree
  examples {
    insert(Leaf, 5) => Node(5, Leaf, Leaf),
    insert(Node(10, Leaf, Leaf), 3) => Node(10, Node(3, Leaf, Leaf), Leaf),
    insert(Node(10, Leaf, Leaf), 15) => Node(10, Leaf, Node(15, Leaf, Leaf)),
  }
{ match t {
    Leaf => Node(n, Leaf, Leaf),
    Node(val, left, right) =>
      if n < val {
        Node(val, insert(left, n), right)
      } else {
        Node(val, left, insert(right, n))
      }
  } }

fn contains(t :: Tree, n :: Int) -> Bool
  examples {
    contains(Leaf, 5) => false,
    contains(Node(10, Leaf, Leaf), 10) => true,
    contains(Node(10, Leaf, Leaf), 5) => false,
  }
{ match t {
    Leaf => false,
    Node(val, left, right) =>
      if n == val {
        true
      } else if n < val {
        contains(left, n)
      } else {
        contains(right, n)
      }
  } }

fn to_sorted_list(t :: Tree) -> List[Int]
  examples {
    to_sorted_list(Leaf) => [],
    to_sorted_list(Node(5, Leaf, Leaf)) => [5],
    to_sorted_list(Node(10, Node(5, Leaf, Leaf), Node(15, Leaf, Leaf))) => [5,10,15],
  }
{ match t {
    Leaf => [],
    Node(val, left, right) =>
      list.concat(to_sorted_list(left), list.concat([val], to_sorted_list(right)))
  } }