import "std.list" as list

type Tree = Leaf | Node(Int, Tree, Tree)

fn insert(t :: Tree, n :: Int) -> Tree
  examples {
    insert(Leaf, 5) => Node(5, Leaf, Leaf),
    insert(Node(10, Leaf, Leaf), 3) => Node(10, Node(3, Leaf, Leaf), Leaf),
    insert(Node(10, Leaf, Leaf), 15) => Node(10, Leaf, Node(15, Leaf, Leaf)),
  }
{ 
  match t {
    Leaf => Node(n, Leaf, Leaf),
    Node(val, left, right) =>
      if n < val {
        Node(val, insert(left, n), right)
      } else {
        Node(val, left, insert(right, n))
      }
  }
}

fn contains(t :: Tree, n :: Int) -> Bool
  examples {
    contains(Leaf, 5) => False,
    contains(Node(10, Node(5, Leaf, Leaf), Leaf), 5) => True,
    contains(Node(10, Node(5, Leaf, Leaf), Leaf), 7) => False,
  }
{ 
  match t {
    Leaf => False,
    Node(val, left, right) =>
      if n == val {
        True
      } else if n < val {
        contains(left, n)
      } else {
        contains(right, n)
      }
  }
}

fn to_sorted_list(t :: Tree) -> List[Int]
  examples {
    to_sorted_list(Leaf) => List.empty(),
    to_sorted_list(Node(2, Leaf, Leaf)) => List.of(2),
    to_sorted_list(Node(10, Node(5, Leaf, Leaf), Node(15, Leaf, Leaf))) => List.of(5, 10, 15),
  }
{ 
  match t {
    Leaf => List.empty(),
    Node(val, left, right) =>
      list.concat(
        to_sorted_list(left),
        list.concat(
          list.of(val),
          to_sorted_list(right)
        )
      )
  }
}