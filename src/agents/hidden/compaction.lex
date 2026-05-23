import "lex-llm/agent" as ag

import "lex-llm/provider" as prov

import "lex-llm/providers" as providers

fn agent() -> ag.AgentDef {
  { name: "compaction", goal: "Summarize the conversation into a concise context that preserves all relevant decisions, code changes, file paths, type errors, and open questions. Return a compact summary in plain text. Omit pleasantries and meta-commentary.", model: prov.claude_sonnet(), provider: providers.anthropic(), tools: [], options: { temperature: None, top_p: None, max_steps: Some(1), max_tokens: Some(2000) } }
}

