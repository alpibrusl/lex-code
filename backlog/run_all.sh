#!/usr/bin/env bash
# run_all.sh [fast|full] [ITEM...]   — one item at a time (one local model), held-out items last.
B="$(cd "$(dirname "$0")" && pwd)"
PROFILE="${1:-fast}"; shift
ITEMS="${*:-$(cd "$B/items" && ls)}"
for held in false true; do
  for i in $ITEMS; do
    h="$(python3 -c "import json;print(str(json.load(open('$B/items/$i/meta.json')).get('held_out',False)).lower())")"
    [ "$h" = "$held" ] && "$B/run_item.sh" "$i" "$PROFILE"
  done
done
