
import "std.list" as list
import "std.result" as Result

// Define the Stack type as a wrapper around a standard list.
type Stack a = list.List a

// Checks if the stack is empty.
fn is_empty(s :: Stack a) -> Bool {
  examples {
    is_empty(list.empty()) => True,
    is_empty(list.cons(1, list.empty())) => False,
  }
  list.is_empty(s)
}

// Adds an element to the top of the stack.
fn push(s :: Stack a, x :: a) -> Stack a {
  examples {
    push(list.empty(), 1) => list.cons(1, list.empty()),
    push(list.cons(1, list.empty()), 2) => list.cons(2, list.cons(1, list.empty())),
  }
  list.cons(x, s)
}

// Views the top element without removing it. Returns None if empty.
fn peek(s :: Stack a) -> Option a {
  examples {
    peek(list.empty()) => None,
    peek(list.cons(1, list.empty())) => Some(1),
    peek(list.cons(2, list.cons(1, list.empty()))) => Some(2),
  }
  list.head(s)
}

// Removes and returns the top element and the new stack.
// Returns Err(s) if the stack is empty.
fn pop(s :: Stack a) -> Result<(a, Stack a), Stack a> {
  examples {
    // Pop from empty stack
    match pop(list.empty()) {
      Err(s) => s, // The error carries the original stack state
      Ok(_) => unreachable,
    }
  }
  match list.tail(s) {
    Some(t) => Ok((list.head(s), t)),
    None => Err(s),
  }
}
