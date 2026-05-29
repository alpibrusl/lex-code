import "std.list" as list
import "std.str"  as str
import "std.int"  as int

# Algebraic expression tree
type Expr = Lit(Int) | Add(Expr, Expr) | Mul(Expr, Expr) | Neg(Expr) | Var(Str)

# Environment: list of (variable name, value) pairs
# Example: [("x", 5), ("y", 3)]
type Env = List[(Str, Int)]

# Evaluate an expression in an environment.
# Returns Err("unbound: <name>") for undefined variables.
fn eval(env :: Env, expr :: Expr) -> Result[Int, Str]
  examples {
    eval([], Lit(5)) => Ok(5),
    eval([], Add(Lit(2), Lit(3))) => Ok(5),
    eval([], Mul(Lit(2), Lit(3))) => Ok(6),
    eval([], Neg(Lit(3))) => Ok(-3),
    eval([("x", 5)], Var("x")) => Ok(5),
    eval([], Var("x")) => Err("unbound: x"),
    eval([("x", 5), ("y", 3)], Add(Var("x"), Var("y"))) => Ok(8),
    eval([("x", 5)], Mul(Var("x"), Neg(Lit(2)))) => Ok(-10),
  }
{
  match expr {
    Lit(n) => Ok(n),
    Add(a, b) => match eval(env, a) {
      Ok(a_val) => match eval(env, b) {
        Ok(b_val) => Ok(a_val + b_val),
        Err(e) => Err(e),
      },
      Err(e) => Err(e),
    },
    Mul(a, b) => match eval(env, a) {
      Ok(a_val) => match eval(env, b) {
        Ok(b_val) => Ok(a_val * b_val),
        Err(e) => Err(e),
      },
      Err(e) => Err(e),
    },
    Neg(a) => match eval(env, a) {
      Ok(a_val) => Ok(-a_val),
      Err(e) => Err(e),
    },
    Var(name) => match list.fold(env, None, fn (acc :: Option[Int], kv :: (Str, Int)) -> Option[Int] {
      match acc {
        Some(_) => acc,
        None => match kv { (k, v) => if k == name { Some(v) } else { None } },
      }
    }) {
      Some(value) => Ok(value),
      None => Err(str.concat("unbound: ", name)),
    },
  }
}

# Convert an expression to a readable string.
# Examples: "5", "(2 + 3)", "(-(3))", "x"
fn to_str(expr :: Expr) -> Str
  examples {
    to_str(Lit(5)) => "5",
    to_str(Add(Lit(2), Lit(3))) => "(2 + 3)",
    to_str(Mul(Lit(2), Lit(3))) => "(2 * 3)",
    to_str(Neg(Lit(3))) => "(-(3))",
    to_str(Var("x")) => "x",
    to_str(Add(Lit(1), Mul(Lit(2), Lit(3)))) => "(1 + (2 * 3))",
    to_str(Neg(Add(Lit(1), Lit(2)))) => "(-((1 + 2)))",
  }
{
  match expr {
    Lit(n) => int.to_str(n),
    Add(a, b) => str.concat("( ", str.concat(to_str(a), str.concat(" + ", str.concat(to_str(b), " ) ")))),
    Mul(a, b) => str.concat("( ", str.concat(to_str(a), str.concat(" * ", str.concat(to_str(b), " ) ")))),
    Neg(a) => str.concat("(-(", str.concat(to_str(a), "))")),
    Var(name) => name,
  }
}