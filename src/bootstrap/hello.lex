import "../server/session" as sess

import "std.str" as str

import "std.io" as io

import "std.int" as int

import "std.list" as list

# Smoke test: drive the Build agent through the LiteLLM proxy (qwen3-coder via
# Ollama) with the curated minimal toolset, asking it to write a Python
# "hello world". Validates the full local stack: lex-code agent loop →
# LiteLLM (OpenAI tool contracts) → Ollama.
fn main() -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval] Nil {
  let provider_tag := "litellm"
  let task := "Create a file named hello.py containing a Python program that prints exactly: Hello, World! Use the write tool to create the file, then stop."
  io.print("[hello] starting build phase via litellm")
  match sess.new_session_with_provider("hello", Build, provider_tag) {
    Err(e) => io.print(str.concat("[hello] session error: ", e)),
    Ok(session) => {
      let result := sess.run_turn_with_provider(session, task, provider_tag)
      let n := list.len(result.steps)
      io.print(str.concat("[hello] done — steps: ", int.to_str(n)))
    },
  }
}

