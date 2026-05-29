import "lex-llm/agent" as ag

import "lex-llm/provider" as prov

import "lex-llm/providers" as providers

import "../tools/index" as tools

import "../permissions/rules" as rules

import "../prompts/explore" as ep

fn agent() -> [env] ag.AgentDef {
  let base := { name: "explore", goal: ep.system(), model: prov.claude_sonnet(), provider: providers.anthropic(), tools: tools.tools_for_spec(rules.explore_permission()), options: { temperature: None, top_p: None, max_steps: Some(20), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.explore_permission())
}

fn mistral_agent() -> [env] ag.AgentDef {
  let base := { name: "explore", goal: ep.system(), model: prov.mistral_small(), provider: providers.mistral(), tools: tools.tools_for_spec(rules.explore_permission()), options: { temperature: None, top_p: None, max_steps: Some(20), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.explore_permission())
}

fn ollama_agent() -> [env] ag.AgentDef {
  let base := { name: "explore", goal: ep.system(), model: prov.ollama(providers.ollama_model()), provider: providers.ollama_local(), tools: tools.tools_for_spec(rules.explore_permission()), options: { temperature: None, top_p: None, max_steps: Some(20), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.explore_permission())
}

fn vllm_agent() -> [env] ag.AgentDef {
  let base := { name: "explore", goal: ep.system(), model: prov.vllm(providers.vllm_model()), provider: providers.vllm_local(), tools: tools.tools_for_spec(rules.explore_permission()), options: { temperature: None, top_p: None, max_steps: Some(20), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.explore_permission())
}

fn openai_agent() -> [env] ag.AgentDef {
  let base := { name: "explore", goal: ep.system(), model: prov.gpt4o_mini(), provider: providers.openai(), tools: tools.tools_for_spec(rules.explore_permission()), options: { temperature: None, top_p: None, max_steps: Some(20), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.explore_permission())
}

fn google_agent() -> [env] ag.AgentDef {
  let base := { name: "explore", goal: ep.system(), model: prov.gemini_flash(), provider: providers.google(), tools: tools.tools_for_spec(rules.explore_permission()), options: { temperature: None, top_p: None, max_steps: Some(20), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.explore_permission())
}

