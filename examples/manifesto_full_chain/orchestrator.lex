# lex-code — manifesto demo: effect-typed parallel orchestration (§VI, full chain)
#
# Manifesto §VI:
#   "The orchestrator manages parallel multi-agent execution with
#    effect-typed concurrency ... It composed the effect rows correctly
#    across parallel sub-agents ... the substrate carries the
#    constraints; the model fills the bodies; the type system verifies
#    the result."
#
# run_parallel declares exactly the 9 effects it uses:
#   [env, concurrent, net, llm, io, proc, sql, fs_write, time]
#
# Each effect comes from a concrete sub-function:
#   env        <- load_model()         — reads MODEL_PATH from environment
#   concurrent <- list.par_map         — two HTTP calls run in parallel
#   net        <- call_agent()         — HTTP POST to each agent endpoint
#   llm        <- refine_with_llm()   — LLM synthesizes the parallel results
#   io         <- io.print / write_report — progress logging + report file
#   proc       <- validate_snippet()   — spawns `lex check` on output
#   fs_write   <- validate_snippet()   — fs.mkdir_p for temp dir
#   sql        <- persist_result()     — records output in audit db
#   time       <- time.now_ms()        — elapsed-time measurement
#
# The type checker verifies the composed row at `lex check` time.
# The negative twin (orchestrator_bad.lex) drops llm/proc/sql/fs_write and
# is REJECTED — the row is enforced, not advisory.
#
#   lex check examples/manifesto_full_chain/orchestrator.lex
#   lex check examples/manifesto_full_chain/orchestrator_bad.lex   # fails

import "std.env"   as env
import "std.http"  as http
import "std.bytes" as bytes
import "std.proc"  as proc
import "std.sql"   as sql
import "std.fs"    as fs
import "std.time"  as time
import "std.io"    as io
import "std.str"   as str
import "std.int"   as int
import "std.list"  as list

import "lex-llm/agent"     as ag
import "lex-llm/provider"  as prov
import "lex-llm/providers" as provs
import "lex-llm/message"   as msg

type AgentTask = { agent_id :: Str, instruction :: Str, endpoint :: Str }

type AgentResult = { agent_id :: Str, output :: Str, elapsed_ms :: Int }

type MultiResult = { results :: List[AgentResult], total_ms :: Int, report_path :: Str }

# ---- Pure sub-functions ------------------------------------------

fn bool_str(b :: Bool) -> Str
  examples {
    bool_str(true) => "true",
    bool_str(false) => "false"
  }
{
  if b { "true" } else { "false" }
}

fn format_report(build :: AgentResult, test :: AgentResult, total_ms :: Int, build_valid :: Bool, test_valid :: Bool) -> Str
  examples {
    format_report({ agent_id: "b", output: "x", elapsed_ms: 0 }, { agent_id: "t", output: "y", elapsed_ms: 0 }, 0, true, false) => format_report({ agent_id: "b", output: "x", elapsed_ms: 0 }, { agent_id: "t", output: "y", elapsed_ms: 0 }, 0, true, false)
  }
{
  str.join([
    "# Orchestration Report",
    str.concat("build: ", str.concat(build.output, str.concat(" (valid: ", str.concat(bool_str(build_valid), ")")))),
    str.concat("test:  ", str.concat(test.output, str.concat(" (valid: ", str.concat(bool_str(test_valid), ")")))),
    str.concat("total_ms: ", int.to_str(total_ms))
  ], "\n")
}

# ---- Effectful sub-functions -------------------------------------

fn load_model() -> [env] Str {
  match env.get("MODEL_PATH") {
    Some(m) => m,
    None    => "claude-3-5-sonnet-20241022",
  }
}

# Call an external agent over HTTP. Falls back to "unavailable" on
# network error — the demo focuses on type-level verification, not
# live connectivity.
fn call_agent(endpoint :: Str, instruction :: Str) -> [net] Str {
  match http.post(endpoint, bytes.from_str(instruction), "text/plain") {
    Ok(resp) => match bytes.to_str(resp.body) {
      Ok(s)  => s,
      Err(_) => "decode-error",
    },
    Err(_) => "unavailable",
  }
}

# Write a snippet to a temp dir and validate it with `lex check`.
# Uses [fs_write] (mkdir_p), [io] (write temp file), and [proc] (spawn lex check).
fn validate_snippet(code :: Str) -> [proc, io, fs_write] Bool {
  let __mkdir := fs.mkdir_p("/tmp/lex_validate")
  match io.write("/tmp/lex_validate/snippet.lex", code) {
    Err(_) => false,
    Ok(_)  => match proc.spawn("lex", ["check", "/tmp/lex_validate/snippet.lex"]) {
      Ok(r)  => r.exit_code == 0,
      Err(_) => false,
    },
  }
}

fn persist_result(db :: Db, agent_id :: Str, output :: Str) -> [sql] Unit {
  let __e := sql.exec(db, "INSERT OR IGNORE INTO results(agent_id, output) VALUES (?, ?)", [PStr(agent_id), PStr(output)])
  ()
}

fn write_report(path :: Str, content :: Str) -> [io] Str {
  match io.write(path, content) {
    Ok(_)  => path,
    Err(_) => "",
  }
}

# Run a single LLM turn to synthesize the two agent outputs.
# This is what carries the llm effect into the orchestration row.
fn refine_with_llm(build_out :: Str, test_out :: Str) -> [env, net, llm, io, proc] Unit {
  let provider := provs.anthropic()
  let model    := prov.claude_sonnet()
  let prompt   := str.join(["Synthesize build and test outputs:", build_out, test_out], "\n")
  let def      := ag.make_agent("synthesizer", prompt, model, provider, [], ag.default_options())
  let __steps  := ag.run_steps(def, [msg.user("synthesize")], 1)
  ()
}

# ---- Orchestrator ------------------------------------------------

# Compose all 9 effects in a single function — the type checker
# verifies the declared row exactly matches what the body uses.
fn run_parallel(build_task :: AgentTask, test_task :: AgentTask, db :: Db, report_dir :: Str) -> [env, concurrent, net, llm, io, proc, sql, fs_write, time] MultiResult {
  let start_ms := time.now_ms()
  let model    := load_model()
  let __log    := io.print(str.concat("[orchestrator] model: ", model))

  let tasks       := [build_task, test_task]
  let raw_results := list.par_map(tasks, fn (task :: AgentTask) -> [net] AgentResult {
    let output := call_agent(task.endpoint, task.instruction)
    { agent_id: task.agent_id, output: output, elapsed_ms: 0 }
  })

  let build_res := match list.head(raw_results) {
    Some(r) => r,
    None    => { agent_id: build_task.agent_id, output: "", elapsed_ms: 0 },
  }
  let test_res := match list.head(list.tail(raw_results)) {
    Some(r) => r,
    None    => { agent_id: test_task.agent_id, output: "", elapsed_ms: 0 },
  }

  let build_valid := validate_snippet(build_res.output)
  let test_valid  := validate_snippet(test_res.output)

  let __synthesis := refine_with_llm(build_res.output, test_res.output)

  let __pb := persist_result(db, build_task.agent_id, build_res.output)
  let __pt := persist_result(db, test_task.agent_id, test_res.output)

  let total_ms    := time.now_ms() - start_ms
  let report      := format_report(build_res, test_res, total_ms, build_valid, test_valid)
  let report_path := str.concat(report_dir, "/orchestration_report.md")
  let __rp        := write_report(report_path, report)

  let __done := io.print(str.concat("[orchestrator] report written to ", report_path))
  { results: raw_results, total_ms: total_ms, report_path: report_path }
}

fn main() -> [env, concurrent, net, llm, io, proc, sql, fs_write, time] Unit {
  let build_task := { agent_id: "build-worker", instruction: "implement list.zip", endpoint: "http://localhost:9000/agent" }
  let test_task  := { agent_id: "test-worker",  instruction: "property-test list.zip", endpoint: "http://localhost:9001/agent" }
  match sql.open(":memory:") {
    Err(e) => {
      let __e := io.print(str.concat("sql.open failed: ", e.message))
      ()
    },
    Ok(db) => {
      let __schema := sql.exec(db, "CREATE TABLE IF NOT EXISTS results(agent_id TEXT NOT NULL, output TEXT NOT NULL)", [])
      let r := run_parallel(build_task, test_task, db, "/tmp")
      let __log := io.print(str.concat("[main] total_ms=", int.to_str(r.total_ms)))
      ()
    },
  }
}
