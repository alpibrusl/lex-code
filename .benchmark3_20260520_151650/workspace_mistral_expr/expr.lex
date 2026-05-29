import "std.list" as list
import "std.str"  as str
import "std.int"  as int

# Algebraic data type for expressions
type Expr = Lit(Int) | Add(Expr, Expr) | Mul(Expr, Expr) | Neg(Expr) | Var(Str)

# Environment: list of (variable name, value) pairs
# Used for variable lookup in `eval`
type Env = List[(Str, Int)]

# Evaluate an expression in a given environment
# Returns Err("unbound: <name>") if a variable is not found
fn eval(env :: Env, expr :: Expr) -> Result[Int, Str]
  examples {
    eval([], Lit(5))                     => Ok(5),
    eval([], Add(Lit(2), Lit(3)))         => Ok(5),
    eval([], Mul(Lit(2), Lit(3)))         => Ok(6),
    eval([], Neg(Lit(3)))                 => Ok(-3),
    eval([("x", 10)], Var("x"))         => Ok(10),
    eval([("x", 10)], Add(Var("x"), Lit(5))) => Ok(15),
    eval([], Var("y"))                   => Err("unbound: y"),
    eval([("x", 10)], Add(Var("x"), Var("y"))) => Err("unbound: y"),
  }
{
  match expr {
    Lit(n)       => Ok(n),
    Add(e1, e2)  => {
      match eval(env, e1) {
        Ok(v1) => {
          match eval(env, e2) {
            Ok(v2)  => Ok(v1 + v2),
            Err(e)  => Err(e),
          }
        },
        Err(e)  => Err(e),
      }
    },
    Mul(e1, e2)  => {
      match eval(env, e1) {
        Ok(v1) => {
          match eval(env, e2) {
            Ok(v2)  => Ok(v1 * v2),
            Err(e)  => Err(e),
          }
        },
        Err(e)  => Err(e),
      }
    },
    Neg(e)       => {
      match eval(env, e) {
        Ok(v)   => Ok(-v),
        Err(e)  => Err(e),
      }
    },
    Var(name)    => {
      match list.find(env, fn(pair) { str.eq(pair.0, name) }) {
        Some((_, val))  => Ok(val),
        None            => Err(str.concat("unbound: ", name)),
      }
    },
  }
}

# Convert an expression to a readable string representation
fn to_str(expr :: Expr) -> Str
  examples {
    to_str(Lit(5))               => "5",
    to_str(Add(Lit(2), Lit(3)))   => "(2 + 3)",
    to_str(Mul(Lit(2), Lit(3)))   => "(2 * 3)",
    to_str(Neg(Lit(3)))           => "(-(3))",
    to_str(Var("x"))            => "x",
    to_str(Add(Var("x"), Lit(5))) => "(x + 5)",
    to_str(Mul(Var("x"), Neg(Lit(3)))) => "(x * (-(3)))",
    to_str(Neg(Add(Lit(1), Lit(2)))) => "(-((1 + 2)))",
  }
{
  match expr {
    Lit(n)       => int.to_str(n),
    Add(e1, e2)  => str.concat("(", str.concat(to_str(e1), str.concat(" + ", str.concat(to_str(e2), ")")))),
    Mul(e1, e2)  => str.concat("(", str.concat(to_str(e1), str.concat(" * ", str.concat(to_str(e2), ")")))),
    Neg(e)       => str.concat("(-(", str.concat(to_str(e), "))")),
    Var(name)    => name,
  }
}