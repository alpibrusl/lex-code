#!/usr/bin/env bash
# scripts/eval.sh — lex-code eval harness (#86)
#
# Runs a fixed set of task specs against a fixed set of providers, each in
# its own `git worktree` checked out from HEAD, and reports pass/fail +
# step counts. Mechanical scoring only — lex check on the touched files,
# the task spec's own criteria (src/task_spec.lex's is_satisfied) — no
# LLM judge. See README's "Eval harness" section for why.
#
# ---- isolation, and the bug this avoids --------------------------------
#
# .lex/verified.jsonl is project-scoped and append-only, with no content
# hash tying a record to what it was a pass of (#91): a stale pass from an
# earlier run on the same target path can satisfy a later, unrelated run's
# criteria even when that later run's edit is broken. Reproduced by hand
# running zip.task against three local models in one working tree without
# clearing state between them.
#
# Each (task, provider) pair below runs in its own git worktree checked
# out fresh from HEAD. Because .lex/ is gitignored, a fresh worktree has
# NO .lex/verified.jsonl at all — there is nothing to inherit and nothing
# to clear.
#
# Consequence: this only ever evaluates the CURRENT COMMIT. Uncommitted
# changes to a task spec or fixture are invisible to it until committed.
#
# Usage:
#   make eval
#   EVAL_PROVIDERS="litellm anthropic" EVAL_TASKS="examples/tasks/zip.task" scripts/eval.sh
#
# Env vars — see the README's eval-harness section for the full table.

set -uo pipefail # not -e: one failed pair must not stop the matrix

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

DEFAULT_TASKS="examples/tasks/zip.task examples/tasks/effect_narrow.task examples/tasks/repair_examples.task examples/tasks/widen_effect.task"
EVAL_TASKS="${EVAL_TASKS:-$DEFAULT_TASKS}"
EVAL_PROVIDERS="${EVAL_PROVIDERS:-litellm}"
EVAL_PIPELINE="${EVAL_PIPELINE:-build}"
EVAL_STRICT="${EVAL_STRICT:-}"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
EVAL_RESULTS_DIR="${EVAL_RESULTS_DIR:-$REPO_ROOT/.lex/eval-runs/$RUN_ID}"
ALLOW_EFFECTS="approval,concurrent,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time"

mkdir -p "$EVAL_RESULTS_DIR"
HEAD_SHA="$(git rev-parse HEAD)"

# Provider tags that need a key in the environment to be usable. Anything
# not listed here (litellm, ollama, vllm, ...) is assumed local and always
# considered configured — its own daemon/URL env vars are the caller's
# responsibility, same as any other lex-code invocation.
provider_required_var() {
  case "$1" in
    anthropic) echo "ANTHROPIC_API_KEY" ;;
    openai) echo "OPENAI_API_KEY" ;;
    google) echo "GOOGLE_API_KEY" ;;
    mistral) echo "MISTRAL_API_KEY" ;;
    opencode) echo "OPENCODE_API_KEY" ;;
    *) echo "" ;;
  esac
}

provider_configured() {
  local var
  var="$(provider_required_var "$1")"
  [ -z "$var" ] || [ -n "${!var:-}" ]
}

RESULTS_FILE="$EVAL_RESULTS_DIR/results.tsv"
: > "$RESULTS_FILE"

for task in $EVAL_TASKS; do
  if [ ! -f "$task" ]; then
    echo "[eval] WARNING: task spec not found: $task (skipping)" >&2
    continue
  fi
  for provider in $EVAL_PROVIDERS; do
    pair="$(basename "$task" .task)__$provider"

    if ! provider_configured "$provider"; then
      var="$(provider_required_var "$provider")"
      echo "[eval] $pair: skipped — \$$var not set" >&2
      printf '%s\t%s\t%s\t%s\t%s\n' "$task" "$provider" "SKIPPED" "0" "-" >> "$RESULTS_FILE"
      if [ -n "$EVAL_STRICT" ]; then
        exit 1
      fi
      continue
    fi

    run_dir="$EVAL_RESULTS_DIR/$pair"
    mkdir -p "$run_dir"
    log_file="$run_dir/run.log"

    worktree_path="$(mktemp -d "${TMPDIR:-/tmp}/lex-eval.XXXXXX")"
    rm -rf "$worktree_path" # git worktree add must create the dir itself
    echo "[eval] $pair: worktree at $worktree_path (from $HEAD_SHA)" >&2

    if ! git worktree add --detach --quiet "$worktree_path" "$HEAD_SHA" >>"$log_file" 2>&1; then
      echo "[eval] $pair: git worktree add FAILED — see $log_file" >&2
      printf '%s\t%s\t%s\t%s\t%s\n' "$task" "$provider" "ERROR" "0" "$log_file" >> "$RESULTS_FILE"
      continue
    fi

    (
      cd "$worktree_path"
      # Defensive assertion, not a fix: a fresh worktree should never have
      # this file (see header). If it ever does, fail loudly here instead
      # of silently reintroducing #91.
      if [ -e ".lex/verified.jsonl" ]; then
        echo "[eval] unexpected .lex/verified.jsonl in a fresh worktree — aborting" >&2
        exit 2
      fi
      lex pkg install >>"$log_file" 2>&1
      LEX_TASK_SPEC="$REPO_ROOT/$task" \
        LEX_PROVIDER="$provider" \
        LEX_PIPELINE="$EVAL_PIPELINE" \
        lex run --allow-effects "$ALLOW_EFFECTS" src/bootstrap/run.lex main >>"$log_file" 2>&1
    )
    run_status=$?

    # Preserve the full trail before the worktree (and its .lex/) is gone.
    if [ -d "$worktree_path/.lex" ]; then
      cp -R "$worktree_path/.lex" "$run_dir/lex-state" 2>/dev/null
    fi

    if [ $run_status -ne 0 ]; then
      echo "[eval] $pair: lex run exited $run_status" >&2
    fi

    git worktree remove --force "$worktree_path" 2>>"$log_file" || rm -rf "$worktree_path"
    git worktree prune

    verdict="NOT SATISFIED"
    if grep -qE '^task ".*": SATISFIED$' "$log_file"; then
      verdict="SATISFIED"
    elif ! grep -qE '^task ".*": (SATISFIED|NOT SATISFIED)$' "$log_file"; then
      verdict="ERROR (no verdict — see $log_file)"
    fi

    steps=0
    while read -r n; do
      steps=$((steps + n))
    done < <(grep -oE 'done — [0-9]+ steps' "$log_file" | grep -oE '[0-9]+')

    printf '%s\t%s\t%s\t%s\t%s\n' "$task" "$provider" "$verdict" "$steps" "$log_file" >> "$RESULTS_FILE"
    echo "[eval] $pair: $verdict ($steps steps)" >&2
  done
done

echo
echo "## lex-code eval — $RUN_ID (HEAD $HEAD_SHA)"
echo
for task in $EVAL_TASKS; do
  [ -f "$task" ] || continue
  printf '%-40s' "$(basename "$task")"
  for provider in $EVAL_PROVIDERS; do
    row="$(awk -F'\t' -v t="$task" -v p="$provider" '$1==t && $2==p {print $3" ("$4" steps)"}' "$RESULTS_FILE")"
    printf '  %-14s %s' "$provider" "${row:-—}"
  done
  echo
done
echo
echo "full trail per run under: $EVAL_RESULTS_DIR/<task>__<provider>/"
