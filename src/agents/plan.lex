import "lex-llm/agent"     as ag
import "lex-llm/provider"  as prov
import "lex-llm/providers" as providers

import "../tools/index"  as tools
import "../prompts/plan" as pp

fn agent() -> ag.AgentDef {
  { name:     "plan",
    goal:     pp.system(),
    model:    prov.claude_sonnet(),
    provider: providers.anthropic(),
    tools:    tools.read_only_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(30), max_tokens: None } }
}

fn mistral_agent() -> ag.AgentDef {
  { name:     "plan",
    goal:     pp.system(),
    model:    prov.mistral_large(),
    provider: providers.mistral(),
    tools:    tools.read_only_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(30), max_tokens: None } }
}
