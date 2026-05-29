import "std.list" as list

type Tree = Leaf | Node(Int, Tree, Tree)

fn insert(t :: Tree, n :: Int) -> Tree
  examples {
    insert(Leaf, 5) => Node(5, Leaf, Leaf),
    insert(Node(10, Leaf, Leaf), 3) => Node(10, Node(3, Leaf, Leaf), Leaf),
    insert(Node(10, Leaf, Leaf), 15) => Node(10, Leaf, Node(15, Leaf, Leaf)),
  }
{ match t {
    Leaf => Node(n, Leaf, Leaf),
    Node(v, left, right) =>
      if n < v {
        Node(v, insert(left, n), right)
      } else {
        Node(v, left, insert(right, n))
      }
  } }

fn contains(t :: Tree, n :: Int) -> Bool
  examples {
    contains(Leaf, 5) => false,
    contains(Node(5, Leaf, Leaf), 5) => true,
    contains(Node(5, Leaf, Leaf), 3) => false,
  }
{ match t {
    Leaf => false,
    Node(v, left, right) =>
      if n = v {
        true
      } else if n < v {
        contains(left, n)
      } else {
        contains(right, n)
      }
  } }

fn to_sorted_list(t :: Tree) -> List[Int]
  examples {
    to_sorted_list(Leaf) => [],
    to_sorted_list(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf))) => [3,5,7],
    to_sorted_list(Node(10, Node(5, Leaf, Leaf), Node(15, Leaf, Leaf))) => [5,10,15],
  }
{ match t {
    Leaf => [],
    Node(v, left, right) =>
      list.concat(list.concat(left, [v]), right)
  } }