# invoices demo — a security brief and the attacks that test it

`brief.txt` asks lex-code for a multi-tenant invoices REST API built from
lex-web, lex-schema and lex-orm. It lists six attacker moves (missing or
forged token, cross-tenant access, SQL injection through a filter, mass
assignment, oversized body, hostile path ids) and requires the server to run
with exactly the `net` and `sql` grants.

`attack.sh` is the check that does not trust the build: it starts the built
server with only `--allow-effects net,sql --allow-net-host 127.0.0.1` and
fires 13 curl requests at it, each expecting a specific status.

## Run it

```bash
mkdir -p /tmp/invoices && cd /tmp/invoices
lex-code --ollama --package "$(cat /path/to/examples/invoices_demo/brief.txt)" \
  --name=invoices --auto --parallel=2 --max-turns=50
sh /path/to/examples/invoices_demo/attack.sh src/invoices.lex
```

`attack.sh` takes the path to the built `invoices.lex`, starts the server
itself (port `INVOICES_PORT`, default 8099) and kills it on exit.
