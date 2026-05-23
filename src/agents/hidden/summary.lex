import "lex-llm/agent" as ag

import "lex-llm/provider" as prov

import "lex-llm/providers" as providers

fn agent() -> ag.AgentDef {
  { name: "summary", goal: "Summarize the key outcomes of this coding session: what was built, what was fixed, what tests were added, what type errors were resolved. Be concrete and brief (2-4 sentences).", model: prov.claude_sonnet(), provider: providers.anthropic(), tools: [], options: { temperature: None, top_p: None, max_steps: Some(1), max_tokens: Some(200) } }
}

