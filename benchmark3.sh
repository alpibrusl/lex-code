#!/usr/bin/env bash
# Lex-code benchmark-3 — four single-file tasks + one multi-file task.
# Models: claude-sonnet-4-6  gpt-4o  mistral-large-latest  glm-4.7-flash:latest  qwen3-coder:30b

set -u

export LEX=/Users/alfonso/Workspace/alpibrusl/lex-lang/target/release/lex
CODEDIR=/Users/alfonso/Workspace/alpibrusl/lex-code
OUTDIR="$CODEDIR/.benchmark3_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

# Load API keys from shell profile if not already set
for _var in ANTHROPIC_API_KEY OPENAI_API_KEY MISTRAL_API_KEY; do
  if [[ -z "${!_var:-}" ]]; then
    _val=$(grep -oE "${_var}=[^ ]+" ~/.zshrc 2>/dev/null | head -1 | cut -d= -f2)
    [[ -n "$_val" ]] && export "${_var}=${_val}"
  fi
done

# ── Tasks ──────────────────────────────────────────────────────────────────

TASK_EXPR="Implement an expression evaluator in Lex. Write a complete file starting with:

import \"std.list\" as list
import \"std.str\"  as str
import \"std.int\"  as int

type Expr = Lit(Int) | Add(Expr, Expr) | Mul(Expr, Expr) | Neg(Expr) | Var(Str)
type Env  = List[(Str, Int)]

Implement these two pure functions, each with an examples block:

  eval(env :: Env, expr :: Expr) -> Result[Int, Str]
  # Returns Err(\"unbound: <name>\") for undefined variables.

  to_str(expr :: Expr) -> Str
  # Readable representation: \"5\", \"(2 + 3)\", \"(-(3))\", \"x\"

Rules: pure functions, # comments, == for equality, NO else if (nest as else { if ... }), body in { }.
If write returns an error, fix the code and call write again."

TASK_RLE="Implement run-length encoding in Lex. Write a complete file starting with:

import \"std.list\" as list
import \"std.int\"  as int

type Run = Segment(Int, Int)   # Segment(count, value)

Implement these three pure functions, each with an examples block:

  encode(xs :: List[Int]) -> List[Run]
  # encode([1,1,2,2,2,3]) => [Segment(2,1), Segment(3,2), Segment(1,3)]

  decode(runs :: List[Run]) -> List[Int]
  # decode([Segment(2,1), Segment(3,2)]) => [1,1,2,2,2]

  roundtrip(xs :: List[Int]) -> Bool
  # roundtrip(xs) must equal true for any xs — decode(encode(xs)) == xs

Rules: pure functions, # comments, == for equality, NO else if (nest as else { if ... }), body in { }.
If write returns an error, fix the code and call write again."

TASK_STACK="Implement a stack-based calculator in Lex. Write a complete file starting with:

import \"std.list\" as list
import \"std.str\"  as str
import \"std.int\"  as int

type Op = Push(Int) | Pop | Add | Mul | Dup | Swap

Implement these two pure functions, each with an examples block:

  step(stack :: List[Int], op :: Op) -> Result[List[Int], Str]
  # Applies one operation to the stack. Returns Err(\"underflow\") when stack too small.
  # Push(n): pushes n. Pop: removes top. Add: pops 2, pushes sum. Mul: pops 2, pushes product.
  # Dup: duplicates top. Swap: swaps top two.

  run(ops :: List[Op]) -> Result[List[Int], Str]
  # Applies all ops starting from empty stack []. Returns final stack or first error.

Rules: pure functions, # comments, == for equality, NO else if (nest as else { if ... }), body in { }.
If write returns an error, fix the code and call write again."

TASK_JSON="Implement a JSON-like value type in Lex. Write a complete file starting with:

import \"std.list\" as list
import \"std.str\"  as str
import \"std.int\"  as int

type Val = VNull | VBool(Bool) | VNum(Int) | VStr(Str) | VArr(List[Val]) | VObj(List[(Str, Val)])

Implement these two pure functions, each with an examples block:

  stringify(v :: Val) -> Str
  # stringify(VNull) => \"null\"
  # stringify(VBool(true)) => \"true\"
  # stringify(VNum(42)) => \"42\"
  # stringify(VStr(\"hi\")) => \"\\\"hi\\\"\"
  # stringify(VArr([VNum(1), VNum(2)])) => \"[1, 2]\"
  # stringify(VObj([(\"a\", VNum(1))])) => \"{\\\"a\\\": 1}\"

  get(v :: Val, key :: Str) -> Option[Val]
  # get(VObj([(\"x\", VNum(1))]), \"x\") => Some(VNum(1))
  # get(VNull, \"x\") => None

Rules: pure functions, # comments, == for equality, NO else if (nest as else { if ... }), body in { }.
If write returns an error, fix the code and call write again."

TASK_MULTIFILE="Implement an expression evaluator split across two files.

File 1 — write to 'types.lex':
  type Expr = Lit(Int) | Add(Expr, Expr) | Mul(Expr, Expr) | Neg(Expr) | Var(Str)
  type Env  = List[(Str, Int)]
  No imports needed.

File 2 — write to 'eval.lex' (imports from types.lex):
  import \"std.list\" as list
  import \"std.str\"  as str
  import \"std.int\"  as int
  import \"./types\"  as t

  fn eval(env :: t.Env, expr :: t.Expr) -> Result[Int, Str]
  fn to_str(expr :: t.Expr) -> Str

Both functions must be pure, have examples blocks, and use t.Lit, t.Add, t.Var etc.
for constructor patterns and expressions (they are in the 't' module namespace).

Rules: pure functions, # comments, == for equality, NO else if (nest as else { if ... }).
If write returns an error on either file, fix and rewrite that file."

TASKS=(
  "expr:$TASK_EXPR"
  "rle:$TASK_RLE"
  "stack:$TASK_STACK"
  "json:$TASK_JSON"
  "multifile:$TASK_MULTIFILE"
)

# ── Model runners ───────────────────────────────────────────────────────────

run_ollama_task() {
  local model="$1" task_name="$2" task_prompt="$3" outdir="$4"
  local slug="${model//[:\/]/_}"
  local taskdir="$outdir/workspace_${slug}_${task_name}"
  local logfile="$outdir/${slug}_${task_name}.log"
  mkdir -p "$taskdir"

  local before after
  before=$(python3 -c "import time; print(int(time.time()*1000))")
  (cd "$taskdir" && OLLAMA_MODEL="$model" perl -e 'alarm 180; exec @ARGV' -- "$LEX" run \
    --allow-effects net,llm,io,proc,sql,time,env,fs_write,fs_read,concurrent \
    --allow-fs-read / \
    --allow-fs-write "$taskdir" \
    --allow-net-host localhost \
    --max-steps 100000000 \
    "$CODEDIR/src/tui/main.lex" main -- --ollama "$task_prompt") \
    > "$logfile" 2>&1 || true
  after=$(python3 -c "import time; print(int(time.time()*1000))")

  echo "$(( (after - before) / 1000 ))s $taskdir $logfile"
}

run_claude_task() {
  local task_name="$1" task_prompt="$2" outdir="$3"
  local taskdir="$outdir/workspace_claude_${task_name}"
  local logfile="$outdir/claude_${task_name}.log"
  mkdir -p "$taskdir"

  local before after
  before=$(python3 -c "import time; print(int(time.time()*1000))")
  (cd "$taskdir" && perl -e 'alarm 300; exec @ARGV' -- "$LEX" run \
    --allow-effects net,llm,io,proc,sql,time,env,fs_write,fs_read,concurrent \
    --allow-fs-read / \
    --allow-fs-write "$taskdir" \
    --allow-net-host api.anthropic.com \
    --max-steps 100000000 \
    "$CODEDIR/src/tui/main.lex" main -- "$task_prompt") \
    > "$logfile" 2>&1 || true
  after=$(python3 -c "import time; print(int(time.time()*1000))")

  echo "$(( (after - before) / 1000 ))s $taskdir $logfile"
}

run_gpt_task() {
  local task_name="$1" task_prompt="$2" outdir="$3"
  local taskdir="$outdir/workspace_gpt4o_${task_name}"
  local logfile="$outdir/gpt4o_${task_name}.log"
  mkdir -p "$taskdir"

  local before after
  before=$(python3 -c "import time; print(int(time.time()*1000))")
  (cd "$taskdir" && perl -e 'alarm 300; exec @ARGV' -- "$LEX" run \
    --allow-effects net,llm,io,proc,sql,time,env,fs_write,fs_read,concurrent \
    --allow-fs-read / \
    --allow-fs-write "$taskdir" \
    --allow-net-host api.openai.com \
    --max-steps 100000000 \
    "$CODEDIR/src/tui/main.lex" main -- --openai "$task_prompt") \
    > "$logfile" 2>&1 || true
  after=$(python3 -c "import time; print(int(time.time()*1000))")

  echo "$(( (after - before) / 1000 ))s $taskdir $logfile"
}

run_mistral_task() {
  local task_name="$1" task_prompt="$2" outdir="$3"
  local taskdir="$outdir/workspace_mistral_${task_name}"
  local logfile="$outdir/mistral_${task_name}.log"
  mkdir -p "$taskdir"

  local before after
  before=$(python3 -c "import time; print(int(time.time()*1000))")
  (cd "$taskdir" && perl -e 'alarm 180; exec @ARGV' -- "$LEX" run \
    --allow-effects net,llm,io,proc,sql,time,env,fs_write,fs_read,concurrent \
    --allow-fs-read / \
    --allow-fs-write "$taskdir" \
    --allow-net-host api.mistral.ai \
    --max-steps 100000000 \
    "$CODEDIR/src/tui/main.lex" main -- --mistral "$task_prompt") \
    > "$logfile" 2>&1 || true
  after=$(python3 -c "import time; print(int(time.time()*1000))")

  echo "$(( (after - before) / 1000 ))s $taskdir $logfile"
}

check_workspace() {
  local taskdir="$1"
  local pass=0 fail=0 files=()

  while IFS= read -r f; do
    files+=("$f")
  done < <(find "$taskdir" -maxdepth 1 -name "*.lex" -type f 2>/dev/null)

  if [[ ${#files[@]} -eq 0 ]]; then
    echo "  no .lex files written"
    return
  fi

  for f in "${files[@]}"; do
    local fname check_result
    fname=$(basename "$f")
    check_result=$("$LEX" check "$f" 2>&1 | head -1)
    if [[ "$check_result" == "ok" ]]; then
      printf "  ✓ %s\n" "$fname"
      (( pass++ )) || true
    else
      printf "  ✗ %s — %s\n" "$fname" "$check_result"
      (( fail++ )) || true
    fi
  done

  if [[ $fail -eq 0 && $pass -gt 0 ]]; then
    printf "  PASS (%d file%s)\n" "$pass" "$([ "$pass" -eq 1 ] && echo '' || echo 's')"
  else
    printf "  FAIL (%d ok / %d error)\n" "$pass" "$fail"
  fi
}

# ── Main ────────────────────────────────────────────────────────────────────

echo "═══════════════════════════════════════════════════════════════"
echo " Benchmark-3: Multi-task evaluation"
echo " Tasks: expr  rle  stack  json  multifile"
echo " Models: claude-sonnet-4-6  gpt-4o  mistral-large-latest  glm-4.7-flash:latest  qwen3-coder:30b"
echo " Output: $OUTDIR"
echo "═══════════════════════════════════════════════════════════════"
echo ""

for task_entry in "${TASKS[@]}"; do
  task_name="${task_entry%%:*}"
  task_prompt="${task_entry#*:}"

  echo "┌── Task: $task_name ──────────────────────────────────────────────"
  echo ""

  # claude sonnet (cloud)
  printf "  ▶ claude-sonnet-4-6\n"
  read -r elapsed taskdir logfile <<< "$(run_claude_task "$task_name" "$task_prompt" "$OUTDIR")"
  printf "    time: %s\n" "$elapsed"
  check_workspace "$taskdir"
  echo ""

  # gpt-4o (cloud)
  printf "  ▶ gpt-4o\n"
  read -r elapsed taskdir logfile <<< "$(run_gpt_task "$task_name" "$task_prompt" "$OUTDIR")"
  printf "    time: %s\n" "$elapsed"
  check_workspace "$taskdir"
  echo ""

  # mistral (cloud)
  printf "  ▶ mistral-large-latest\n"
  read -r elapsed taskdir logfile <<< "$(run_mistral_task "$task_name" "$task_prompt" "$OUTDIR")"
  printf "    time: %s\n" "$elapsed"
  check_workspace "$taskdir"
  echo ""

  # glm (local ollama)
  printf "  ▶ glm-4.7-flash:latest\n"
  read -r elapsed taskdir logfile <<< "$(run_ollama_task "glm-4.7-flash:latest" "$task_name" "$task_prompt" "$OUTDIR")"
  printf "    time: %s\n" "$elapsed"
  check_workspace "$taskdir"
  echo ""

  # qwen3-coder (local ollama)
  printf "  ▶ qwen3-coder:30b\n"
  read -r elapsed taskdir logfile <<< "$(run_ollama_task "qwen3-coder:30b" "$task_name" "$task_prompt" "$OUTDIR")"
  printf "    time: %s\n" "$elapsed"
  check_workspace "$taskdir"
  echo ""

  echo "└──────────────────────────────────────────────────────────────"
  echo ""
done

echo "Done. Full logs in $OUTDIR"
