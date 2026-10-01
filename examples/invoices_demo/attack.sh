#!/bin/sh
# Start the built server with exactly the grants it should need, then attack it.
# usage: attack.sh <path-to-invoices.lex>
set -u
SRC=${1:?path to invoices.lex}
export INVOICES_TOKENS="tok-acme:acme,tok-globex:globex" INVOICES_PORT=${INVOICES_PORT:-8099}
B=http://127.0.0.1:$INVOICES_PORT
lex run --allow-effects net,sql --allow-net-host 127.0.0.1 "$SRC" main >/tmp/invoices-server.log 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT
i=0; until curl -s -o /dev/null "$B/" || [ $i -gt 50 ]; do i=$((i+1)); sleep 0.2; done
req() { printf '%-52s -> ' "$1"; shift; curl -s -o /tmp/inv.body -w '%{http_code}' "$@"; printf '  %s\n' "$(head -c 90 /tmp/inv.body)"; }
A="Authorization: Bearer tok-acme"; G="Authorization: Bearer tok-globex"; J="Content-Type: application/json"
req "no token"                         "$B/invoices"
req "unknown token"                    -H "Authorization: Bearer nope" "$B/invoices"
req "acme creates an invoice"          -H "$A" -H "$J" -d '{"customer":"Initech","amount_cents":4200,"currency":"EUR"}' "$B/invoices"
req "acme reads it"                    -H "$A" "$B/invoices/1"
req "globex reads acme's invoice (IDOR)" -H "$G" "$B/invoices/1"
req "globex reads a missing id"        -H "$G" "$B/invoices/999"
req "globex pays acme's invoice"       -H "$G" -X POST "$B/invoices/1/pay"
req "SQL injection in customer filter" -H "$A" -G --data-urlencode "customer=x' OR '1'='1" "$B/invoices"
req "mass assignment (tenant, paid)"   -H "$A" -H "$J" -d '{"customer":"X","amount_cents":1,"currency":"USD","tenant":"globex","paid":true}' "$B/invoices"
req "negative amount"                  -H "$A" -H "$J" -d '{"customer":"X","amount_cents":-5,"currency":"USD"}' "$B/invoices"
req "oversized body"                   -H "$A" -H "$J" -d "{\"customer\":\"$(head -c 5000 /dev/zero | tr '\0' a)\",\"amount_cents\":1,\"currency\":\"USD\"}" "$B/invoices"
req "path traversal id"                -H "$A" "$B/invoices/..%2f..%2fetc%2fpasswd"
req "acme pays its own invoice"        -H "$A" -X POST "$B/invoices/1/pay"
