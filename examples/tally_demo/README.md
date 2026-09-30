# tally demo — the human brief

`brief.txt` is the literal, unedited prompt a human wrote for the lex-code demo
video: a small expense-splitting package ("tally") with eight functions, a
float-rounding trap, and an invariants paragraph. Nothing in it names Lex
idioms, stdlib modules or a file layout; lex-code plans, builds, gates and
hardens the package from this text alone.

## Run it

```bash
mkdir -p /tmp/tally && cd /tmp/tally
export OPENCODE_API_KEY=...            # OpenCode Go plan
export OPENCODE_MODEL=qwen3.8-flash
lex-code --opencode --package "$(cat /path/to/examples/tally_demo/brief.txt)" \
  --name=tally --auto --parallel=2 --max-turns=50
```

Local, free alternative (slower): replace `--opencode` with the Ollama
provider and `qwen3.8:27b-mlx`.

## What to expect

- A plan of 8 units with about 14 invariants, filed as typed issues.
- A deterministic gate (`lex check`, examples, invariants) that accepts or
  rejects each unit; the final `[PROJECT_VERDICT]` / `[PACKAGE_GATE]` lines
  are the result, not the model's own claim.
- Wall-clock is dominated by model inference, not by Lex tooling. In the
  recorded run, planning took 49.4 min, of which ~96.5% was waiting on LLM
  steps and ~4% was tool execution (the whole deterministic gate took 5.3 s,
  a `lex check` 0.45 s). Session audit trails in `.lex/sessions/*.db` let you
  reproduce that split: LLM time is the gap before each `llm.step` event,
  tool time is `cap.completed` minus `cap.invoked`.
