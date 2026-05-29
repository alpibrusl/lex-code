import "std.list" as list
import "std.str"  as str
import "std.int"  as int

type Expr = Lit(Int) | Add(Expr, Expr) | Mul(Expr, Expr) | Neg(Expr) | Var(Str)
type Env  = List[(Str, Int)]

fn eval(env :: Env, expr :: Expr) -> Result[Int, Str]
  examples {
    eval([], Lit(5)) => Ok(5),
    eval([("x", 10)], Var("x")) => Ok(10),
    eval([], Var("y")) => Err("unbound: y"),
    eval([("x", 3), ("y", 4)], Add(Var("x"), Var("y"))) => Ok(7),
    eval([("x", 2)], Neg(Var("x"))) => Ok(-2),
  }
{
  match expr {
    Lit(n) => Ok(n),
    Add(e1, e2) => match eval(env, e1) {
      Ok(v1) => match eval(env, e2) {
        Ok(v2) => Ok(v1 + v2),
        Err(e) => Err(e),
      },
      Err(e) => Err(e),
    },
    Mul(e1, e2) => match eval(env, e1) {
      Ok(v1) => match eval(env, e2) {
        Ok(v2) => Ok(v1 * v2),
        Err(e) => Err(e),
      },
      Err(e) => Err(e),
    },
    Neg(e) => match eval(env, e) {
      Ok(v) => Ok(-v),
      Err(e) => Err(e),
    },
    Var(name) => match list.fold(env, None, fn (acc :: Option[Int], kv :: (Str, Int)) -> Option[Int] {
      match acc {
        Some(v) => Some(v),
        None => match kv {
          (k, v) => if k == name { Some(v) } else { None },
        },
      }
    }) {
      Some(v) => Ok(v),
      None => Err(str.concat("unbound: ", name)),
    },
  }
}

fn to_str(expr :: Expr) -> Str
  examples {
    to_str(Lit(42)) => "42",
    to_str(Add(Lit(2), Lit(3))) => "(2 + 3)",
    to_str(Mul(Var("x"), Lit(5))) => "(x * 5)",
    to_str(Neg(Var("y"))) => "(-(y))",
  }
{
  match expr {
    Lit(n) => int.to_str(n),
    Add(e1, e2) => str.concat("(", str.concat(str.concat(to_str(e1), " + "), str.concat(to_str(e2), ")"))),
    Mul(e1, e2) => str.concat("(", str.concat(str.concat(to_str(e1), " * "), str.concat(to_str(e2), ")"))),
    Neg(e) => str.concat("(-(", str.concat(to_str(e), "))")),
    Var(name) => name,
  }
}