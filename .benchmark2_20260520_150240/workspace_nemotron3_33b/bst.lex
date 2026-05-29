import "std.list" as list

type Tree = Leaf | Node(Int, Tree, Tree)

fn insert(t :: Tree, n :: Int) -> Tree
  examples {
    insert(Leaf, 5) => Node(5, Leaf, Leaf),
    insert(Node(10, Leaf, Leaf), 3) => Node(10, Node(3, Leaf, Leaf), Leaf),
  }
{ match t {
    Leaf => Node(n, Leaf, Leaf),
    Node(_, left, right) =>
      if n < _
      { insert(left, n) } else { insert(right, n) }
  } }

fn contains(t :: Tree, n :: Int) -> Bool
  examples {
    contains(Leaf, 5) => false,
    contains(Node(10, Leaf, Leaf), 10) => true,
    contains(Node(10, Leaf, Leaf), 5) => false,
  }
{ match t {
    Leaf => false,
    Node(_, left, right) =>
      if n == _
      { true } else { if n < _
        { contains(left, n) } else { contains(right, n) } }
  } }

fn to_sorted_list(t :: Tree) -> List[Int]
  examples {
    to_sorted_list(Node(10, Node(5, Leaf, Leaf), Node(15, Leaf, Leaf))) => List[5, 10, 15],
  }
{ match t {
    Leaf => List.nil(),
    Node(_, left, right) =>
      list.concat(
        to_sorted_list(left),
        list.concat(
          list.cons(_, List.nil()),
          to_sorted_list(right)
        )
      )
  } }