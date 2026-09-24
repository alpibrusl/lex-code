#!/usr/bin/env bash
# Verifies "Eval harness" (README) end to end: a real, isolated (git
# worktree) task-spec run against Ollama, reporting SATISFIED/FAILED —
# mechanical scoring, no LLM judge. Scoped to one task (zip.task) so this
# stays fast; `make eval` alone runs all four against the default provider.
#
# Usage: bash examples/eval_harness_quick.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/.."

EVAL_PROVIDERS="ollama" EVAL_TASKS="examples/tasks/zip.task" scripts/eval.sh
