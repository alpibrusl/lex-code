# Expression evaluator and pretty-printer

import "std.list" as list
import "std.str"  as str
import "std.int"  as int
import "./types"  as t

# Evaluate an expression in a given environment.
# Returns Err if a variable is unbound.
fn eval(env :: t.Env, expr :: t.Expr) -> Result[Int, Str]
  examples {
    eval([], t.Lit(42)) => Ok(42),
    eval([], t.Add(t.Lit(2), t.Lit(3))) => Ok(5),
    eval([], t.Mul(t.Lit(2), t.Lit(3))) => Ok(6),
    eval([], t.Neg(t.Lit(5))) => Ok(-5),
    eval([("x", 10)], t.Var("x")) => Ok(10),
    eval([], t.Var("y")) => Err("unbound variable: y"),
    eval([("a", 2), ("b", 3)], t.Add(t.Var("a"), t.Var("b"))) => Ok(5),
  }
{
  match expr {
    t.Lit(n)       => Ok(n),
    t.Add(e1, e2) => match eval(env, e1) {
      Ok(v1) => match eval(env, e2) {
        Ok(v2) => Ok(v1 + v2),
        Err(e) => Err(e),
      },
      Err(e) => Err(e),
    },
    t.Mul(e1, e2) => match eval(env, e1) {
      Ok(v1) => match eval(env, e2) {
        Ok(v2) => Ok(v1 * v2),
        Err(e) => Err(e),
      },
      Err(e) => Err(e),
    },
    t.Neg(e)      => match eval(env, e) {
      Ok(v)  => Ok(int.neg(v)),
      Err(e) => Err(e),
    },
    t.Var(name)   => match list.fold(env, None, fn (acc :: Option[Int], kv :: (Str, Int)) -> Option[Int] {
      match acc {
        Some(_) => acc,
        None    => match kv { (k, v) => if k == name { Some(v) } else { None } },
      }
    }) {
      Some(v) => Ok(v),
      None    => Err(str.concat("unbound variable: ", name)),
    },
  }
}

# Convert an expression to a string.
fn to_str(expr :: t.Expr) -> Str
  examples {
    to_str(t.Lit(42)) => "42",
    to_str(t.Add(t.Lit(2), t.Lit(3))) => "(2 + 3)",
    to_str(t.Mul(t.Lit(2), t.Lit(3))) => "(2 * 3)",
    to_str(t.Neg(t.Lit(5))) => "-5",
    to_str(t.Var("x")) => "x",
    to_str(t.Add(t.Var("a"), t.Mul(t.Lit(2), t.Var("b")))) => "(a + (2 * b))",
  }
{
  match expr {
    t.Lit(n)       => int.to_str(n),
    t.Add(e1, e2) => str.concat("( ", str.concat(to_str(e1), str.concat(" + ", str.concat(to_str(e2), " )")))),
    t.Mul(e1, e2) => str.concat("( ", str.concat(to_str(e1), str.concat(" * ", str.concat(to_str(e2), " )")))),
    t.Neg(e)      => str.concat("-", to_str(e)),
    t.Var(name)   => name,
  }
}