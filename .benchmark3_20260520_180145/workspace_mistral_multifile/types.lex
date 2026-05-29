# Algebraic data types for expressions and environment

type Expr =
  | Lit(Int)          # Literal integer
  | Add(Expr, Expr)   # Addition
  | Mul(Expr, Expr)   # Multiplication
  | Neg(Expr)         # Unary negation
  | Var(Str)          # Variable reference

# Environment: list of (variable name, value) pairs
type Env = List[(Str, Int)]