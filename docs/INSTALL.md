# Install and run

[README](../README.md) · [All docs](../README.md#documentation)

How to install lex-code, and how to start it.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/alpibrusl/lex-code/main/install.sh | bash
```

Installs the pinned Lex toolchain (only if `lex` isn't already on your
PATH — an existing install is left alone), resolves lex-code's own
package dependencies, and installs the `lex-code` binary via the
repo's own `make install` below. Safe to re-run. macOS and Linux; on
Windows, use WSL. Override the prefix with `LEX_CODE_PREFIX=~/.local`.

```sh
# fully local, no key
lex-code --ollama "implement list.zip"

# or OpenCode Go
export OPENCODE_API_KEY=...
lex-code --opencode "implement list.zip"
```

## Install from a checkout (what `install.sh` runs for you)

Already have a clone, want a custom prefix, or don't want to pipe a
script into bash — this is what the one-liner above does under the hood:

```sh
lex pkg install    # fetch lex-llm, lex-agent, and the rest

# installs to /usr/local/bin/lex-code and /usr/local/lib/lex-code/
make install

# custom prefix
make install PREFIX=~/.local

# uninstall
make uninstall
```

After install, `lex` must still be on your PATH (it’s the interpreter).

```sh
lex-code "implement list.zip"
lex-code --plan --ollama "how should we structure the session module?"
```

## Quickstart

Use `bin/lex-code` rather than calling `lex run` by hand: it supplies
the capability grant every session needs, the `main --` separator that
stops your first flag being read as a function name, and a raised
`--max-steps` — the VM's 10,000,000-step default is a DoS guard for
untrusted sandboxed snippets, not for a long agentic session, and a
verbose provider's ordinary output can hit it outright partway through
a real task. Calling `lex run` directly (as the rest of this README
does, for entry points other than the TUI) needs the same flag added
by hand; see `bin/lex-code`'s own comment for the full story.

```sh
# fully local, no key — build mode (default), interactive REPL
./bin/lex-code --ollama

# one-shot CLI mode (exits after the task)
./bin/lex-code --ollama "implement list.zip"

# plan mode
./bin/lex-code --plan --ollama

# OpenCode Go provider
export OPENCODE_API_KEY=...
./bin/lex-code --opencode

# bootstrap demo: impl → spec → test → review
lex run src/bootstrap/run.lex

# web UI + HTTP API on :7700 (see Web Frontend)
lex run --max-steps 20000000000 --allow-effects approval,concurrent,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time \
  src/server/web.lex serve_web
```
