import "std.list" as list

type Tree = Leaf | Node(Int, Tree, Tree)

fn insert(t :: Tree, n :: Int) -> Tree
  examples {
    insert(Leaf, 5) => Node(5, Leaf, Leaf),
    insert(Node(10, Leaf, Leaf), 5) => Node(10, Node(5, Leaf, Leaf), Leaf),
    insert(Node(10, Node(5, Leaf, Leaf), Leaf), 15) => Node(10, Node(5, Leaf, Leaf), Node(15, Leaf, Leaf)),
    insert(Node(10, Node(5, Leaf, Leaf), Node(15, Leaf, Leaf)), 10) => Node(10, Node(5, Leaf, Leaf), Node(15, Leaf, Leaf)),
  }
  match t {
    Leaf => Node(n, Leaf, Leaf),
    Node(val, left, right) =>
      if n < val {
        Node(val, insert(left, n), right)
      } else if n > val {
        Node(val, left, insert(right, n))
      } else {
        Node(val, left, right)
      }
  }

fn contains(t :: Tree, n :: Int) -> Bool
  examples {
    contains(Leaf, 5) => false,
    contains(Node(5, Leaf, Leaf), 5) => true,
    contains(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)), 4) => false,
    contains(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)), 6) => false,
    contains(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf)), 7) => true,
  }
  match t {
    Leaf => false,
    Node(val, left, right) =>
      if n == val {
        true
      } else if n < val {
        contains(left, n)
      } else {
        contains(right, n)
      }
  }

fn to_sorted_list(t :: Tree) -> List[Int]
  examples {
    to_sorted_list(Leaf) => [],
    to_sorted_list(Node(5, Leaf, Leaf)) => [5],
    to_sorted_list(Node(5, Node(3, Leaf, Leaf), Node(7, Leaf, Leaf))) => [3,5,7],
    to_sorted_list(Node(10, Node(5, Leaf, Leaf), Node(15, Leaf, Leaf))) => [5,10,15],
  }
  match t {
    Leaf => [],
    Node(val, left, right) =>
      list.concat(
        to_sorted_list(left),
        list.concat(
          [val],
          to_sorted_list(right)
        )
      )
  }