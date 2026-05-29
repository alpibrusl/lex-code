# Algebraic data types for expressions and environment

type Expr = 
  Lit(Int) |
  Add(Expr, Expr) |
  Mul(Expr, Expr) |
  Neg(Expr) |
  Var(Str)

# Environment: list of (variable name, value) pairs
type Env = List[(Str, Int)]