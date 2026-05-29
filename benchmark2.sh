#!/usr/bin/env bash
# Lex-code benchmark-2 — harder task, top-3 models only.
# Task: binary search tree with custom ADT, pattern matching, multiple pure fns.

set -uo pipefail

TASK="Implement a binary search tree in Lex. Write the complete file starting with this exact header:\n\nimport \"std.list\" as list\n\ntype Tree = Leaf | Node(Int, Tree, Tree)\n\nThen implement these three pure functions, each with an examples {} block BEFORE the function body:\n\n  insert(t :: Tree, n :: Int) -> Tree\n  contains(t :: Tree, n :: Int) -> Bool\n  to_sorted_list(t :: Tree) -> List[Int]   # in-order traversal returns sorted list\n\nRules:\n- All functions must be pure (no effects annotation)\n- Use # for comments, not //\n- Equality check is == not =\n- NO else if — Lex only has if/else, nest as: else { if ... { } else { } }\n- Function body MUST be wrapped in { } even when it starts with match\n\nIMPORTANT: If write returns an error, read the error carefully, fix the code, and call write again."

LEX=/Users/alfonso/Workspace/alpibrusl/lex-lang/target/release/lex
CODEDIR=/Users/alfonso/Workspace/alpibrusl/lex-code
OUTDIR="$CODEDIR/.benchmark2_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

MODELS=(
  "glm-4.7-flash:latest"
  "nemotron3:33b"
  "qwen3-coder:30b"
)

run_model() {
  local model="$1"
  local slug="${model//[:\/]/_}"
  local logfile="$OUTDIR/${slug}.log"
  local before after elapsed

  echo "▶ $model"

  local tmpdir="$OUTDIR/workspace_${slug}"
  mkdir -p "$tmpdir"

  before=$(python3 -c "import time; print(int(time.time()*1000))")
  (cd "$tmpdir" && OLLAMA_MODEL="$model" "$LEX" run \
    --allow-effects net,llm,io,proc,sql,time,env,fs_write,fs_read,concurrent \
    --allow-fs-read / \
    --allow-fs-write "$tmpdir" \
    --allow-net-host localhost \
    --max-steps 100000000 \
    "$CODEDIR/src/tui/main.lex" main -- --ollama "$TASK") \
    > "$logfile" 2>&1 || true
  after=$(python3 -c "import time; print(int(time.time()*1000))")
  elapsed=$(( after - before ))

  local written_files
  written_files=$(find "$tmpdir" -maxdepth 1 -type f | wc -l | tr -d ' ')

  printf "  time: %ds   files written: %s\n" "$(( elapsed / 1000 ))" "$written_files"

  # Type-check each written .lex file
  if [[ "$written_files" -gt 0 ]]; then
    while IFS= read -r f; do
      local fname lines check_result
      fname=$(basename "$f")
      lines=$(wc -l < "$f")
      printf "  ── %s (%d lines)\n" "$fname" "$lines"
      if [[ "$f" == *.lex ]]; then
        check_result=$("$LEX" check "$f" 2>&1 | head -1)
        printf "     lex check: %s\n" "$check_result"
      fi
    done < <(find "$tmpdir" -maxdepth 1 -type f)
  fi

  printf "  output:\n"
  sed 's/^/    /' "$logfile"
  echo
}

echo "═══════════════════════════════════════════════════════"
echo " Benchmark-2: Binary Search Tree"
echo " Models: ${MODELS[*]}"
echo " Output: $OUTDIR"
echo "═══════════════════════════════════════════════════════"
echo

for model in "${MODELS[@]}"; do
  run_model "$model"
  echo "───────────────────────────────────────────────────────"
done

echo "Done. Full logs in $OUTDIR"
