import "lex-llm/agent"     as ag
import "lex-llm/provider"  as prov
import "lex-llm/providers" as providers

import "../tools/index"         as tools
import "../prompts/test_agent"  as tp

fn agent() -> ag.AgentDef {
  { name:     "test",
    goal:     tp.system(),
    model:    prov.claude_sonnet(),
    provider: providers.anthropic(),
    tools:    tools.test_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(30), max_tokens: None } }
}

fn mistral_agent() -> ag.AgentDef {
  { name:     "test",
    goal:     tp.system(),
    model:    prov.codestral(),
    provider: providers.mistral(),
    tools:    tools.test_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(30), max_tokens: None } }
}
