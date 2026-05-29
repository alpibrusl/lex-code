# Expression evaluator in Lex

import "std.list" as list

import "std.str" as str

import "std.int" as int

# Algebraic data types for expressions and environments
type Expr = Lit(Int) | Add((Expr, Expr)) | Mul((Expr, Expr)) | Neg(Expr) | Var(Str)

type Env = List[(Str, Int)]

# Evaluates an expression in a given environment.
# Returns Err("unbound: <name>") for undefined variables.
fn eval(env :: Env, expr :: Expr) -> Result[Int, Str]
  examples {
    eval([], Lit(5)) => Ok(5),
    eval([], Add(Lit(2), Lit(3))) => Ok(5),
    eval([], Mul(Lit(2), Lit(3))) => Ok(6),
    eval([], Neg(Lit(3))) => Ok(-3),
    eval([("x", 10)], Var("x")) => Ok(10),
    eval([], Var("y")) => Err("unbound: y"),
    eval([("a", 2), ("b", 3)], Add(Var("a"), Var("b"))) => Ok(5),
    eval([("a", 2)], Mul(Var("a"), Neg(Lit(3)))) => Ok(-6)
  }
{
  match expr {
    Lit(n) => Ok(n),
    Add(l, r) => match eval(env, l) {
      Ok(lv) => match eval(env, r) {
        Ok(rv) => Ok(lv + rv),
        Err(e) => Err(e),
      },
      Err(e) => Err(e),
    },
    Mul(l, r) => match eval(env, l) {
      Ok(lv) => match eval(env, r) {
        Ok(rv) => Ok(lv * rv),
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
        Some(_) => acc,
        None => match kv {
          (k, v) => if k == name {
            Some(v)
          } else {
            None
          },
        },
      }
    }) {
      Some(v) => Ok(v),
      None => Err(str.concat("unbound: ", name)),
    },
  }
}

# Returns a readable string representation of an expression.
fn to_str(expr :: Expr) -> Str
  examples {
    to_str(Lit(5)) => "5",
    to_str(Add(Lit(2), Lit(3))) => "(2 + 3)",
    to_str(Mul(Lit(2), Lit(3))) => "(2 * 3)",
    to_str(Neg(Lit(3))) => "(-(3))",
    to_str(Var("x")) => "x",
    to_str(Add(Lit(1), Mul(Lit(2), Lit(3)))) => "(1 + (2 * 3))",
    to_str(Mul(Add(Lit(1), Lit(2)), Lit(3))) => "((1 + 2) * 3)",
    to_str(Neg(Add(Lit(1), Lit(2)))) => "(-(1 + 2))"
  }
{
  match expr {
    Lit(n) => int.to_str(n),
    Add(l, r) => str.concat("(", str.concat(to_str(l), str.concat(" + ", str.concat(to_str(r), ")")))),
    Mul(l, r) => str.concat("(", str.concat(to_str(l), str.concat(" * ", str.concat(to_str(r), ")")))),
    Neg(e) => str.concat("(-(", str.concat(to_str(e), "))")),
    Var(name) => name,
  }
}

