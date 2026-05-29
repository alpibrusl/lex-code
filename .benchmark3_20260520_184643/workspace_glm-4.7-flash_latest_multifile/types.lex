# Expression types for a simple expression evaluator

type Expr = Lit(Int) | Add(Expr, Expr) | Mul(Expr, Expr) | Neg(Expr) | Var(Str)

type Env = List[(Str, Int)]