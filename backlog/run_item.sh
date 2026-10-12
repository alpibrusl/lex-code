#!/usr/bin/env bash
# run_item.sh ITEM [fast|full]
#   Build one backlog item from scratch with lex-code-overnight, audit it independently,
#   mine its trails for candidate lessons, and append one row to results.tsv.
#   fast = one attempt retry, one repair round, one 2 h round (finds traps cheaply)
#   full = the supervisor's defaults (for "can it finish at all")
set -u
B="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$B/.." && pwd)"
LEXCODE_DIR="${LEX_CODE_DIR:-$ROOT}"          # the lex-code under test: use a clone nobody is editing
LESSONS_DIR="${LEX_CODE_LESSONS_DIR:-$LEXCODE_DIR}"   # --lessons only reads trails
RUNS="${BACKLOG_RUNS:-$B/runs}"
ITEM="$1"; PROFILE="${2:-fast}"
PROV="${LEX_PROVIDER_FLAGS:---ollama}"   # e.g. --vllm with VLLM_BASE_URL/VLLM_MODEL exported
TAG="${RUN_TAG:-}"                       # appended to the profile in the directory and the results row
IDIR="$B/items/$ITEM"
[ -d "$IDIR" ] || { echo "no such item: $ITEM" >&2; exit 2; }
PKG="$(python3 -c "import json;print(json.load(open('$IDIR/meta.json'))['package'])")"
KIND="$(python3 -c "import json;print(json.load(open('$IDIR/meta.json'))['kind'])")"
RUN="$RUNS/$ITEM-$PROFILE$TAG-$(date +%m%d-%H%M)"
mkdir -p "$RUN" && cp "$IDIR/brief.txt" "$RUN/brief.txt"
printf '[package]\nname = "%s"\nversion = "0.1.0"\n' "$PKG" > "$RUN/lex.toml"
case "$PROFILE" in
  fast) FLAGS="--max-attempts=2 --repair-rounds=1 --stall-rounds=1 --max-hours=2 --round-hours=2" ;;
  full) FLAGS="--max-hours=6 --round-hours=3" ;;
  *) echo "profile must be fast or full" >&2; exit 2 ;;
esac
START=$(date +%s)
( cd "$RUN" && "$LEXCODE_DIR/bin/lex-code-overnight" --name="$PKG" --brief-file=brief.txt $PROV --max-turns=60 $FLAGS > overnight.out 2>&1 )
SECS=$(( $(date +%s) - START ))
VERDICT="$(grep -m1 -o '\*\*Verdict:\*\* `[^`]*`' "$RUN/.lex/overnight/REPORT.md" 2>/dev/null | sed 's/.*`\(.*\)`.*/\1/' | cut -c1-40)"
UNITS="$(grep -m1 -o 'Units verified:\*\* [0-9]* / [0-9]*' "$RUN/.lex/overnight/REPORT.md" 2>/dev/null | sed 's/.*\*\* //')"
if [ "$KIND" = lib ]; then
  python3 "$B/audit_lib.py" "$IDIR" "$RUN" > "$RUN/audit.txt" 2>&1
else
  python3 "$IDIR/attack.py" "$RUN" > "$RUN/audit.txt" 2>&1
fi
AUDIT="$(tail -n1 "$RUN/audit.txt" | sed 's/\[AUDIT\] //;s/\[ATTACK\] //')"
( cd "$RUN" && "$LESSONS_DIR/bin/lex-code" --lessons="$PKG" --min-sessions=2 > lessons.md 2>/dev/null )
printf '%s\t%s\t%s\t%s\t%s\t%ss\t%s\t%s\n' "$ITEM" "$PROFILE$TAG" "${VERDICT:-?}" "${UNITS:-?}" "${AUDIT:-?}" "$SECS" "$(cd "$LEXCODE_DIR" && git rev-parse --short HEAD)" "$RUN" >> "$B/results.tsv"
echo "$ITEM $PROFILE: verdict=${VERDICT:-?} units=${UNITS:-?} audit=${AUDIT:-?} (${SECS}s) -> $RUN"
