import "std.list" as list

type Tree = Leaf | Node(Int, Tree, Tree)

fn insert(t :: Tree, n :: Int) -> Tree
  examples {
    insert(Leaf, 5) => Node(5, Leaf, Leaf),
    insert(Node(3, Leaf, Leaf), 5) => Node(3, Leaf, Node(5, Leaf, Leaf)),
    insert(Node(3, Leaf, Leaf), 1) => Node(3, Node(1, Leaf, Leaf), Leaf),
  }
{
  match t {
    Leaf => Node(n, Leaf, Leaf),
    Node(v, left, right) => 
      if n == v { Node(v, left, right) }
      else { 
        if n < v { Node(v, insert(left, n), right) }
        else { Node(v, left, insert(right, n)) }
      },
  }
}

fn contains(t :: Tree, n :: Int) -> Bool
  examples {
    contains(Leaf, 5) => false,
    contains(Node(3, Leaf, Leaf), 3) => true,
    contains(Node(3, Leaf, Leaf), 5) => false,
    contains(Node(3, Node(1, Leaf, Leaf), Node(5, Leaf, Leaf)), 1) => true,
  }
{
  match t {
    Leaf => false,
    Node(v, left, right) => 
      if n == v { true }
      else { 
        if n < v { contains(left, n) }
        else { contains(right, n) }
      },
  }
}

fn to_sorted_list(t :: Tree) -> List[Int]
  examples {
    to_sorted_list(Leaf) => [],
    to_sorted_list(Node(3, Leaf, Leaf)) => [3],
    to_sorted_list(Node(3, Node(1, Leaf, Leaf), Node(5, Leaf, Leaf))) => [1, 3, 5],
  }
{
  match t {
    Leaf => [],
    Node(v, left, right) => 
      list.concat(to_sorted_list(left), list.concat([v], to_sorted_list(right))),
  }
}