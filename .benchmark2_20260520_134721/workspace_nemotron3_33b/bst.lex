import "std.list" as list

type Tree = Leaf | Node(Int, Tree, Tree)

fn insert(t :: Tree, n :: Int) -> Tree
  examples {
    insert(Leaf, 5) => Node(5, Leaf, Leaf),
    insert(Node(10, Leaf, Leaf), 5) => Node(10, Node(5, Leaf, Leaf), Leaf),
  }
{ match t {
      Leaf => Node(n, Leaf, Leaf),
      Node(v, l, r) =>
        if n < v {
          Node(v, insert(l, n), r)
        } else {
          Node(v, l, insert(r, n))
        }
    } }

fn contains(t :: Tree, n :: Int) -> Bool
  examples {
    contains(Leaf, 5) => false,
    contains(Node(10, Leaf, Leaf), 5) => false,
    contains(Node(10, Node(5, Leaf, Leaf), Leaf), 5) => true,
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
    to_sorted_list(Leaf) => [],
    to_sorted_list(Node(2, Leaf, Node(3, Leaf, Leaf))) => [2,3],
  }
{ match t {
      Leaf => [],
      Node(v, l, r) =>
        list.concat(to_sorted_list(l), list.concat([v], to_sorted_list(r)))
    } }