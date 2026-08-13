# CLAUDE.md — lex-code

> Copy this file into the root of any Lex project repository as
> `CLAUDE.md` (read by Claude Code), `AGENTS.md` (read by Cursor /
> Aider / Codex CLI / Copilot CLI), or both. This repo ships both,
> kept in sync — read `AGENTS.md` in full before writing code.

This repository is a **Lex** project — a Lex-native coding assistant
(agents, tools, TUI, A2A/ACP servers). `AGENTS.md` carries the full
discipline, including why this repo has no `tests/` directory and how
provider support is wired across seven agent files plus
`session.lex`.

## The loop

```sh
lex pkg install
lex check <each src/*.lex file>   # no tests/ dir — see AGENTS.md for the CI gate
lex fmt --check src/
```

See `AGENTS.md` for the full discipline.
