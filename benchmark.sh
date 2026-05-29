#!/usr/bin/env bash
# Lex-code model benchmark — same task, all local Ollama models.
# Usage: ./benchmark.sh [task]

set -uo pipefail

TASK="${1:-write a pure Lex function that computes the nth Fibonacci number recursively, with examples}"
LEX=/Users/alfonso/Workspace/alpibrusl/lex-lang/target/release/lex
CODEDIR=/Users/alfonso/Workspace/alpibrusl/lex-code
OUTDIR="$CODEDIR/.benchmark_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

MODELS=(
  "granite4.1:3b"
  "gemma4:latest"
  "mistral-small:latest"
  "glm-4.7-flash:latest"
  "gemma4:26b"
  "qwen3.6:latest"
  "nemotron3:33b"
  "qwen3-coder:30b"
)

run_model() {
  local model="$1"
  local slug="${model//[:\/]/_}"
  local logfile="$OUTDIR/${slug}.log"
  local before after elapsed

  echo "▶ $model"

  # clear any files the previous model wrote so we capture only this run
  local tmpdir="$OUTDIR/workspace_${slug}"
  mkdir -p "$tmpdir"

  before=$(python3 -c "import time; print(int(time.time()*1000))")
  # Run from tmpdir so relative writes (e.g. "fib.lex") land in the isolated workspace.
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

  local files written_files
  written_files=$(find "$tmpdir" -maxdepth 1 -type f | wc -l | tr -d ' ')

  printf "  time: %ds   files written: %s\n" "$(( elapsed / 1000 ))" "$written_files"
  if [[ "$written_files" -gt 0 ]]; then
    while IFS= read -r f; do
      printf "  ── %s (%d lines)\n" "$(basename "$f")" "$(wc -l < "$f")"
    done < <(find "$tmpdir" -maxdepth 1 -type f)
  fi
  printf "  output:\n"
  sed 's/^/    /' "$logfile"
  echo
}

echo "═══════════════════════════════════════════════════════"
echo " Task: $TASK"
echo " Models: ${MODELS[*]}"
echo " Output: $OUTDIR"
echo "═══════════════════════════════════════════════════════"
echo

for model in "${MODELS[@]}"; do
  run_model "$model"
  echo "───────────────────────────────────────────────────────"
done

echo "Done. Full logs in $OUTDIR"
