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
    eval([("x", 2), ("y", 3)], Add(Var("x"), Var("y"))) => Ok(5),
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
        Some(v) => Some(v),
        None => match kv {
          (k, v) => if k == name { Some(v) } else { None },
        },
      }
    }) {
      Some(val) => Ok(val),
      None => Err(str.concat("unbound: ", name)),
    },
  }
}

fn to_str(expr :: Expr) -> Str
  examples {
    to_str(Lit(5)) => "5",
    to_str(Add(Lit(2), Lit(3))) => "(2 + 3)",
    to_str(Neg(Lit(3))) => "(-(3))",
    to_str(Var("x")) => "x",
  }
{
  match expr {
    Lit(n) => int.to_str(n),
    Add(a, b) => str.concat("(", str.concat(str.concat(to_str(a), " + "), to_str(b)), ")"),
    Mul(a, b) => str.concat("(", str.concat(str.concat(to_str(a), " * "), to_str(b)), ")"),
    Neg(a) => str.concat("(-(", to_str(a), "))"),
    Var(name) => name,
  }
}