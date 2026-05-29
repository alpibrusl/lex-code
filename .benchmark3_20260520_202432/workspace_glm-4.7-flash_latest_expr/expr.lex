import "std.list" as list

import "std.str" as str

import "std.int" as int

type Expr = Lit(Int) | Add((Expr, Expr)) | Mul((Expr, Expr)) | Neg(Expr) | Var(Str)

type Env = List[(Str, Int)]

fn eval(env :: Env, expr :: Expr) -> Result[Int, Str]
  examples {
    eval([], Lit(5)) => Ok(5),
    eval([], Var("x")) => Err("unbound: x"),
    eval([("x", 10)], Lit(5)) => Ok(5),
    eval([("x", 10)], Add(Lit(2), Lit(3))) => Ok(5),
    eval([("x", 10)], Mul(Lit(2), Lit(3))) => Ok(6),
    eval([("x", 10)], Neg(Lit(3))) => Ok(-3),
    eval([("x", 10)], Add(Var("x"), Lit(5))) => Ok(15)
  }
{
  match expr {
    Lit(n) => Ok(n),
    Var(name) => {
      match list.head(env) {
        Some((k, v)) => if k == name {
          Ok(v)
        } else {
          eval(list.tail(env), expr)
        },
        None => Err(str.concat("unbound: ", name)),
      }
    },
    Add(lhs, rhs) => {
      match eval(env, lhs) {
        Ok(l) => {
          match eval(env, rhs) {
            Ok(r) => Ok(l + r),
            Err(e) => Err(e),
          }
        },
        Err(e) => Err(e),
      }
    },
    Mul(lhs, rhs) => {
      match eval(env, lhs) {
        Ok(l) => {
          match eval(env, rhs) {
            Ok(r) => Ok(l * r),
            Err(e) => Err(e),
          }
        },
        Err(e) => Err(e),
      }
    },
    Neg(expr) => {
      match eval(env, expr) {
        Ok(v) => Ok(-v),
        Err(e) => Err(e),
      }
    },
  }
}

fn to_str(expr :: Expr) -> Str
  examples {
    to_str(Lit(5)) => "5",
    to_str(Add(Lit(2), Lit(3))) => "(2 + 3)",
    to_str(Neg(Lit(3))) => "(-(3))",
    to_str(Var("x")) => "x",
    to_str(Mul(Var("x"), Lit(2))) => "((x * 2))",
    to_str(Neg(Add(Lit(1), Lit(2)))) => "(-(1 + 2))"
  }
{
  match expr {
    Lit(n) => int.to_str(n),
    Var(name) => name,
    Neg(e) => str.concat("(-( ", to_str(e), "))"),
    Add(lhs, rhs) => str.concat("(", str.concat(to_str(lhs), " + "), to_str(rhs), ")"),
    Mul(lhs, rhs) => str.concat("(", str.concat(to_str(lhs), " * "), to_str(rhs), ")"),
  }
}

