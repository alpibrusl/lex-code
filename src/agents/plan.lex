import "lex-llm/agent"     as ag
import "lex-llm/provider"  as prov
import "lex-llm/providers" as providers

import "../tools/index"  as tools
import "../prompts/plan" as pp

fn agent() -> [env] ag.AgentDef {
  { name:     "plan",
    goal:     pp.system(),
    model:    prov.claude_sonnet(),
    provider: providers.anthropic(),
    tools:    tools.read_only_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(30), max_tokens: None } }
}

fn mistral_agent() -> [env] ag.AgentDef {
  { name:     "plan",
    goal:     pp.system(),
    model:    prov.mistral_large(),
    provider: providers.mistral(),
    tools:    tools.read_only_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(30), max_tokens: None } }
}

fn ollama_agent() -> [env] ag.AgentDef {
  { name:     "plan",
    goal:     pp.system(),
    model:    prov.ollama("gemma4:latest"),
    provider: providers.ollama_local(),
    tools:    tools.read_only_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(30), max_tokens: None } }
}

fn vllm_agent() -> [env] ag.AgentDef {
  { name:     "plan",
    goal:     pp.system(),
    model:    prov.vllm(providers.vllm_model()),
    provider: providers.vllm_local(),
    tools:    tools.read_only_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(30), max_tokens: None } }
}
