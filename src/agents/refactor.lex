import "lex-llm/agent"     as ag
import "lex-llm/provider"  as prov
import "lex-llm/providers" as providers

import "../tools/index"      as tools
import "../prompts/refactor" as rp

fn agent() -> ag.AgentDef {
  { name:     "refactor",
    goal:     rp.system(),
    model:    prov.claude_sonnet(),
    provider: providers.anthropic(),
    tools:    tools.refactor_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(40), max_tokens: None } }
}

fn mistral_agent() -> ag.AgentDef {
  { name:     "refactor",
    goal:     rp.system(),
    model:    prov.codestral(),
    provider: providers.mistral(),
    tools:    tools.refactor_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(40), max_tokens: None } }
}

fn ollama_agent() -> ag.AgentDef {
  { name:     "refactor",
    goal:     rp.system(),
    model:    prov.ollama("codellama"),
    provider: providers.ollama_local(),
    tools:    tools.refactor_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(40), max_tokens: None } }
}
