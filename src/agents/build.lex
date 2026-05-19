import "lex-llm/agent"     as ag
import "lex-llm/provider"  as prov
import "lex-llm/providers" as providers

import "../tools/index"   as tools
import "../prompts/build" as bp

fn agent() -> [env] ag.AgentDef {
  { name:     "build",
    goal:     bp.system(),
    model:    prov.claude_sonnet(),
    provider: providers.anthropic(),
    tools:    tools.all_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(50), max_tokens: None } }
}

fn mistral_agent() -> [env] ag.AgentDef {
  { name:     "build",
    goal:     bp.system(),
    model:    prov.mistral_large(),
    provider: providers.mistral(),
    tools:    tools.all_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(50), max_tokens: None } }
}

fn ollama_agent() -> [env] ag.AgentDef {
  { name:     "build",
    goal:     bp.system(),
    model:    prov.ollama("gemma4:latest"),
    provider: providers.ollama_local(),
    tools:    tools.all_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(50), max_tokens: None } }
}

fn vllm_agent() -> [env] ag.AgentDef {
  { name:     "build",
    goal:     bp.system(),
    model:    prov.vllm(providers.vllm_model()),
    provider: providers.vllm_local(),
    tools:    tools.all_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(50), max_tokens: None } }
}
