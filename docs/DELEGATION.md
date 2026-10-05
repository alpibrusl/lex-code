# Delegating to lex-code from another agent

[README](../README.md) · [All docs](../README.md#documentation)

Use lex-code as a tool from Claude Code, Cursor, Codex or any agent that can run a shell command.

## Delegating to it from another agent (Claude Code, etc.)

_Runnable: `examples/delegate_via_typed_issue.sh`_

`lex-code` is a plain CLI — any agent that can shell out (Claude Code's
own Bash tool, a CI step, another script) can hand it a Lex-specific task
directly, non-interactively, the same one-shot mode above:

```sh
lex-code --ollama "implement list.zip" > /tmp/lex-code.log 2>&1
```

That's fine for a quick delegated edit, but the transcript is prose — a
calling agent shouldn't trust "looks like it worked" any more than a
human should. For a result worth trusting without reading the diff
yourself, hand it a
[typed issue](MODES.md#implementing-a-typed-issue) instead: it iterates against
the type checker and the issue's own acceptance examples, and the run
ends with one machine-readable line regardless of what the model claims:

```sh
lex issue create --title "digit_sum" --shape typed_delta \
  --api 'digit_sum:(n :: Int) -> Int:added' \
  --example 'digit_sum(1234) => 10' --example 'digit_sum(-56) => 11'

lex-code --issue=<id> --ollama > /tmp/lex-code.log 2>&1
grep '^\[ISSUE_VERDICT\]' /tmp/lex-code.log   # verified|failed|inconclusive|unavailable
```

A calling agent branches on that line, not on anything the model said —
`verified` is backed by the type checker and the issue's examples
actually passing, not by a transcript claiming success.

### A packaged skill for other agents

[`skills/lex-code/SKILL.md`](../skills/lex-code/SKILL.md) is this section,
packaged for an agent to install and follow directly — install/provider
selection/both delegation patterns, in ~80 lines, every command in it
verified against this repo. For Claude Code: copy the directory into
`~/.claude/skills/` (or a project's `.claude/skills/`) and it's picked
up automatically:

```sh
mkdir -p ~/.claude/skills
cp -r skills/lex-code ~/.claude/skills/lex-code
```

For Codex or any other agent that reads a plain instructions file rather
than a skills directory, just point it at the same file — it carries no
Claude-Code-specific tool syntax, only shell commands.
