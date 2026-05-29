import "std.list" as list
import "std.str"  as str
import "std.int"  as int

# Algebraic expression type
type Expr = Lit(Int) | Add(Expr, Expr) | Mul(Expr, Expr) | Neg(Expr) | Var(Str)

# Environment: list of (variable name, value) pairs
# Example: [("x", 5), ("y", 3)]
type Env = List[(Str, Int)]

# Evaluate an expression in an environment.
# Returns Err("unbound: <name>") for undefined variables.
fn eval(env :: Env, expr :: Expr) -> Result[Int, Str]
  examples {
    eval([], Lit(5))                     => Ok(5),
    eval([], Add(Lit(2), Lit(3)))        => Ok(5),
    eval([], Mul(Lit(2), Lit(3)))        => Ok(6),
    eval([], Neg(Lit(3)))                => Ok(-3),
    eval([("x", 5)], Var("x"))         => Ok(5),
    eval([], Var("x"))                 => Err("unbound: x"),
    eval([("x", 5)], Add(Var("x"), Lit(3))) => Ok(8),
    eval([("x", 5), ("y", 3)], Mul(Var("x"), Var("y"))) => Ok(15),
  }
{
  match expr {
    Lit(n)       => Ok(n),
    Add(e1, e2)  => match eval(env, e1) {
                      Ok(v1) => match eval(env, e2) {
                                  Ok(v2) => Ok(v1 + v2),
                                  Err(e) => Err(e),
                                },
                      Err(e) => Err(e),
                    },
    Mul(e1, e2)  => match eval(env, e1) {
                      Ok(v1) => match eval(env, e2) {
                                  Ok(v2) => Ok(v1 * v2),
                                  Err(e) => Err(e),
                                },
                      Err(e) => Err(e),
                    },
    Neg(e)       => match eval(env, e) {
                      Ok(v)  => Ok(-v),
                      Err(e) => Err(e),
                    },
    Var(name)    => match list.fold(env, None, fn (acc :: Option[Int], kv :: (Str, Int)) -> Option[Int] {
                                      match kv {
                                        (k, v) => if k == name { Some(v) } else { acc }
                                      }
                                    }) {
                      Some(v) => Ok(v),
                      None    => Err(str.concat("unbound: ", name)),
                    },
  }
}

# Convert an expression to a readable string.
# Examples: "5", "(2 + 3)", "(-(3))", "x"
fn to_str(expr :: Expr) -> Str
  examples {
    to_str(Lit(5))               => "5",
    to_str(Add(Lit(2), Lit(3)))  => "(2 + 3)",
    to_str(Mul(Lit(2), Lit(3)))  => "(2 * 3)",
    to_str(Neg(Lit(3)))          => "(-(3))",
    to_str(Var("x"))           => "x",
    to_str(Add(Lit(1), Mul(Lit(2), Lit(3)))) => "(1 + (2 * 3))",
    to_str(Neg(Add(Lit(1), Lit(2)))) => "(-((1 + 2)))",
  }
{
  match expr {
    Lit(n)       => int.to_str(n),
    Add(e1, e2)  => str.concat("( ", str.concat(to_str(e1), str.concat(" + ", str.concat(to_str(e2), " )")))),
    Mul(e1, e2)  => str.concat("( ", str.concat(to_str(e1), str.concat(" * ", str.concat(to_str(e2), " )")))),
    Neg(e)       => str.concat("(-(", str.concat(to_str(e), "))")),
    Var(name)    => name,
  }
}