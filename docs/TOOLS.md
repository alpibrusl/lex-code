# Tools

[README](../README.md) · [All docs](../README.md#documentation)

The tools an agent can call, and how to add external ones over MCP.

## Tools

### Standard tools (all modes)

| Tool | Description |
|------|-------------|
| `read_file` | Read file contents |
| `write_file` | Write / create a file |
| `edit_file` | Targeted string replacement |
| `grep` | Search file contents by regex |
| `glob` | List files matching a glob |
| `bash` | Run a shell command (killed after 300 s; a background process outlives the call, but only for what is left of those 300 s) |
| `todo_write` | Write structured TODO list |

`write_file` and `edit_file` replace a file atomically — the new content is written beside
it and renamed over it — so a run that is killed mid-edit leaves the old file or the new one,
never a truncated one (which would stall a whole package build, whose units share one source
file). A file's mode and a symbolic link are kept as they were.

After a `.lex` write or edit the tool formats the file, runs `lex check`, and adds one non-blocking
warning when a line builds JSON by joining strings (`str.concat("{\"id\":", ...)`). Two builds
that ended `done` did this and answered with invalid JSON (a reply missing its closing brace;
a customer name with a quote in it spliced in unescaped); the unit examples all passed. The
warning points at `jv.stringify(JObj([...]))`, which escapes and closes. It is a heuristic on the
line text, so a constant JSON string, an example line and a comment are left alone.

### Lex tools

| Tool | Description |
|------|-------------|
| `lex_check` | Type-check a Lex file |
| `lex_audit` | Effect audit |
| `lex_run` | Run a Lex expression |
| `lex_test` | Run tests |
| `lex_stdlib` | Look up or keyword-search the stdlib, signatures from the compiler |
| `find_packages` | Search existing packages by what they do (`lex pkg search`) |
| `package_api` | An installed package's modules, or one module's typed signatures and docs |
| `plan_check` | Planner only: validate the plan file against the build's own rules |
| `issue_show` | Render a typed issue's acceptance as the contract to implement |
| `issue_verify` | Evaluate a typed issue at head, record an `IssueVerified` attestation |
| `issue_propose` | Propose a typed acceptance for a free-form issue (a human approves it) |

### Spec tools

| Tool | Description |
|------|-------------|
| `lex_spec_check` | Evaluate a Spec against bindings |
| `lex_spec_smt` | SMT-backed spec verification |

### Store tools

| Tool | Description |
|------|-------------|
| `sigid_lookup` | Resolve a SigId to a function |
| `attestation_query` | List attestations for a function |
| `effects_of` | Query effect row of a function |
| `lex_store_diff` | Diff two store snapshots |
| `lex_store_apply` | Apply a store patch |
| `lex_store_merge` | Merge two store snapshots |

### VCS tools (lex-vcs / AST-level)

The agent can read and drive lex-vcs directly via these tools.

| Tool | CLI command | Description |
|------|-------------|-------------|
| `ast_diff` | `lex diff <a> <b>` | AST-level diff between two files |
| `op_show` | `lex op show <id>` | Inspect a content-addressed operation |
| `op_log` | `lex op log` | Show the operation log |
| `op_push` | `lex op push` | Push ops to remote |
| `op_pull` | `lex op pull` | Pull ops from remote |
| `branch_list` | `lex branch list` | List branches |
| `branch_current` | `lex branch current` | Show active branch |
| `branch_show` | `lex branch show <name>` | Inspect a branch |
| `branch_create` | `lex branch create <name>` | Create a branch |
| `branch_use` | `lex branch use <name>` | Switch branch |
| `branch_peek` | `lex branch peek <name>` | Read-only view of another branch |
| `branch_overlay` | `lex branch overlay <name>` | Overlay a branch without switching |
| `merge_start` | `lex merge start <branch>` | Begin a merge session |
| `merge_status` | `lex merge status` | Show pending conflicts |
| `merge_resolve` | `lex merge resolve <id>` | Resolve a conflict |
| `merge_defer` | `lex merge defer <id>` | Defer a conflict for later |
| `merge_commit` | `lex merge commit` | Commit a completed merge |

## External tools (MCP)

lex-code has been an MCP *server* for a while — `src/server/mcp_main.lex`
exposes its agents to Claude Desktop. It is now also a **client**, so an issue
tracker, a CI system or a package registry can be a tool the agent calls.

`.lex/mcp.toml` (an example ships at `docs/mcp.toml.example`):

```toml
[[servers]]
url   = "http://localhost:3000"
allow = ["search_issues", "create_pr"]
modes = ["build", "refactor"]      # optional; defaults to build only
```

Tools arrive named `mcp__<tool>` — `mcp__search_issues`. The prefix is not
cosmetic: without it a server offering a tool called `write` or `bash` would
shadow a local one in the dispatcher's name lookup.

### Two gates, and both are needed

**`allow` is the operator's gate** — which of a server's tools this project
loads at all. An empty or missing `allow` list loads **nothing**. The opposite
reading ("no filter configured, so no filtering") is how a server that adds a
tool next week gets it into the prompt without anyone deciding.

**`modes` is the agent's gate** — which agent modes get them, defaulting to
`build` alone. Build's permission spec already permits everything, so that is
the one mode where adding a tool grants no new authority to a restricted
agent. An explore-mode agent that must not `write` does not reach an MCP tool
that writes unless you say so.

The issue asked for an `mcp_tool(name)` predicate in `permissions/rules.lex`.
There deliberately isn't one: lex-spec has no string-prefix operator so it
cannot be written, and permission enforcement is still tool-list based rather
than spec-based, so `modes` is the gate that actually runs. `rules.lex`
records what Phase 2 will need.

### Failure is reported, never silent

A server that is down, a config that will not parse, a name in `allow` the
server does not offer — each yields no tools and a printed note. The session
still starts: an unrelated outage should not become a total outage. But a tool
that quietly vanishes is the failure this codebase keeps finding (#32, #74),
so the absence is always said out loud.

Tools are loaded once per turn rather than cached. A cached list goes stale
silently — a server that changes what it offers, or goes away, would keep
being advertised to the model until the process restarted.
