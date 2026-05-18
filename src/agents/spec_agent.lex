import "lex-llm/agent"     as ag
import "lex-llm/provider"  as prov
import "lex-llm/providers" as providers

import "../tools/index"         as tools
import "../prompts/spec_agent"  as sp

fn agent() -> ag.AgentDef {
  { name:     "spec",
    goal:     sp.system(),
    model:    prov.claude_sonnet(),
    provider: providers.anthropic(),
    tools:    tools.spec_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(30), max_tokens: None } }
}

fn mistral_agent() -> ag.AgentDef {
  { name:     "spec",
    goal:     sp.system(),
    model:    prov.codestral(),
    provider: providers.mistral(),
    tools:    tools.spec_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(30), max_tokens: None } }
}
