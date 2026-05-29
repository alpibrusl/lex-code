import "std.list" as list
import "std.str"  as str
import "std.int"  as int

type Expr = Lit(Int) | Add(Expr, Expr) | Mul(Expr, Expr) | Neg(Expr) | Var(Str)
type Env  = List[(Str, Int)]

fn eval(env :: Env, expr :: Expr) -> Result[Int, Str]
  examples {
    eval([], Lit(5))               => Ok(5),
    eval([], Var("x"))             => Err("unbound: x"),
    eval([("x", 3)], Var("x"))     => Ok(3),
    eval([("x", 3)], Add(Lit(2), Var("x"))) => Ok(5),
    eval([("x", 3)], Mul(Lit(2), Var("x"))) => Ok(6),
    eval([], Neg(Lit(5)))          => Ok(-5),
    eval([("y", 4)], Neg(Var("y"))) => Ok(-4),
  }
{ match expr {
  Lit(v) => Ok(v),
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
  Var(name) => match list.find(env, name) {
    Some(v) => Ok(v),
    None => Err("unbound: " + name),
  },
} }

fn to_str(expr :: Expr) -> Str
  examples {
    to_str(Lit(5))       => "5",
    to_str(Var("x"))     => "x",
    to_str(Add(Lit(2), Lit(3))) => "(2 + 3)",
    to_str(Mul(Lit(2), Lit(3))) => "(2 * 3)",
    to_str(Neg(Lit(5)))  => "-(5)",
  }
{ match expr {
  Lit(v) => int.to_str(v),
  Var(name) => name,
  Add(e1, e2) => "(" + to_str(e1) + " + " + to_str(e2) + ")",
  Mul(e1, e2) => "(" + to_str(e1) + " * " + to_str(e2) + ")",
  Neg(e) => "-(" + to_str(e) + ")",
} }