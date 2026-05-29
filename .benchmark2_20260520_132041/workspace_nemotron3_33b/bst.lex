import "std.list" as list

type Tree = Leaf | Node(Int, Tree, Tree)

fn insert(t :: Tree, n :: Int) -> Tree
  examples {
    insert(Leaf, 5) => Node(5, Leaf, Leaf),
    insert(Node(3, Leaf, Leaf), 2) => Node(3, Node(2, Leaf, Leaf), Leaf),
    insert(Node(3, Leaf, Leaf), 5) => Node(3, Leaf, Node(5, Leaf, Leaf)),
  }
{ match t {
      Leaf => Node(n, Leaf, Leaf),
      Node(v, l, r) =>
        if n < v {
          Node(v, insert(l, n), r)
        } else if n > v {
          Node(v, l, insert(r, n))
        } else {
          Node(v, l, r)
        }
    } }

fn contains(t :: Tree, n :: Int) -> Bool
  examples {
    contains(Leaf, 5) => false,
    contains(Node(3, Leaf, Leaf), 3) => true,
    contains(Node(3, Leaf, Leaf), 5) => false,
  }
{ match t {
      Leaf => false,
      Node(v, l, r) =>
        if n == v {
          true
        } else if n < v {
          contains(l, n)
        } else {
          contains(r, n)
        }
    } }

fn to_sorted_list(t :: Tree) -> List[Int]
  examples {
    to_sorted_list(Leaf) => List.nil,
    to_sorted_list(Node(5, Leaf, Node(10, Leaf, Leaf))) => List.cons(5, List.cons(10, List.nil)),
  }
{ match t {
      Leaf => List.nil,
      Node(v, l, r) =>
        list.concat(to_sorted_list(l), list.concat(List.cons(v), to_sorted_list(r)))
    } }