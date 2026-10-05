# Architecture

[README](../README.md) · [All docs](../README.md#documentation)

How lex-code is put together.

## Architecture

```
lex-code
├── src/
│   ├── agents/          # AgentDef values (build, plan, explore, refactor, spec, test, review, bar)
│   ├── bar/             # Minimum-bar ledger, probe ids, repository probes
│   ├── prompts/         # System prompts per mode
│   ├── tools/           # Tool implementations
│   │   ├── standard/    # read, write, edit, grep, glob, bash, todowrite
│   │   ├── lex_*.lex    # check, audit, run, test, spec_check, spec_smt
│   │   ├── lex_store_*  # sigid, attestations, effects, diff, apply, merge
│   │   └── vcs/         # 17 lex-vcs tools (ast_diff, op_*, branch_*, merge_*)
│   ├── permissions/     # lex-spec Spec values per agent mode
│   ├── server/
│   │   ├── session.lex        # Session type, run_turn, AgentMode
│   │   ├── session_events.lex # Durable conversation record (the trail)
│   │   ├── multi_agent.lex    # std.conc parallel dispatch
│   │   ├── persist.lex        # lex-trail log helpers
│   │   ├── web.lex            # HTTP: static src/web + POST /a2a  (runnable)
│   │   ├── mcp_main.lex       # MCP + A2A agent card on :7778     (runnable)
│   │   └── client_protocol.lex # Zed ACP over stdio, Phase 1      (runnable)
│   ├── tui/main.lex     # CLI REPL + one-shot mode
│   ├── web/             # Web frontend (vanilla JS)
│   └── bootstrap/run.lex  # Demo 4-phase pipeline
├── bin/lex-code      # Shell wrapper (used by make install)
├── Makefile          # install / uninstall targets
└── lex.toml
```
