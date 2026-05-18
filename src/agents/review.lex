import "lex-llm/agent"     as ag
import "lex-llm/provider"  as prov
import "lex-llm/providers" as providers

import "../tools/index"    as tools
import "../prompts/review" as rvp

fn agent() -> ag.AgentDef {
  { name:     "review",
    goal:     rvp.system(),
    model:    prov.claude_sonnet(),
    provider: providers.anthropic(),
    tools:    tools.review_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(25), max_tokens: None } }
}

fn mistral_agent() -> ag.AgentDef {
  { name:     "review",
    goal:     rvp.system(),
    model:    prov.mistral_large(),
    provider: providers.mistral(),
    tools:    tools.review_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(25), max_tokens: None } }
}

fn ollama_agent() -> ag.AgentDef {
  { name:     "review",
    goal:     rvp.system(),
    model:    prov.ollama("codellama"),
    provider: providers.ollama_local(),
    tools:    tools.review_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(25), max_tokens: None } }
}
