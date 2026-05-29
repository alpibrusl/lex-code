import "std.list" as list
import "std.str" as str
import "std.int" as int

# Algebraic expression type
type Expr = Lit(Int) | Add(Expr, Expr) | Mul(Expr, Expr) | Neg(Expr) | Var(Str)

# Environment: list of (variable name, value) pairs
type Env = List[(Str, Int)]

# Lookup a variable in the environment.
fn lookup(env :: Env, name :: Str) -> Option[Int] {
  list.fold(env, None, fn (acc :: Option[Int], kv :: (Str, Int)) -> Option[Int] {
    match acc {
      Some(_) => acc,
      None => match kv { (k, v) => if k == name { Some(v) } else { None } },
    }
  })
}