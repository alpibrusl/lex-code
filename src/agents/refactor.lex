import "lex-llm/agent" as ag

import "lex-llm/provider" as prov

import "lex-llm/providers" as providers

import "../tools/index" as tools

import "../permissions/rules" as rules

import "../prompts/refactor" as rp

fn agent() -> [env] ag.AgentDef {
  let base := { name: "refactor", goal: rp.system(), model: prov.claude_sonnet(), provider: providers.anthropic(), tools: tools.tools_for_spec(rules.refactor_permission()), options: { temperature: None, top_p: None, max_steps: Some(40), max_tokens: None } }
  ag.with_permission_gate(base, rules.refactor_permission())
}

fn mistral_agent() -> [env] ag.AgentDef {
  let base := { name: "refactor", goal: rp.system(), model: prov.mistral_large(), provider: providers.mistral(), tools: tools.tools_for_spec(rules.refactor_permission()), options: { temperature: None, top_p: None, max_steps: Some(40), max_tokens: None } }
  ag.with_permission_gate(base, rules.refactor_permission())
}

fn ollama_agent() -> [env] ag.AgentDef {
  let base := { name: "refactor", goal: rp.system(), model: prov.ollama(providers.ollama_model()), provider: providers.ollama_local(), tools: tools.tools_for_spec(rules.refactor_permission()), options: { temperature: None, top_p: None, max_steps: Some(40), max_tokens: None } }
  ag.with_permission_gate(base, rules.refactor_permission())
}

fn vllm_agent() -> [env] ag.AgentDef {
  let base := { name: "refactor", goal: rp.system(), model: prov.vllm(providers.vllm_model()), provider: providers.vllm_local(), tools: tools.tools_for_spec(rules.refactor_permission()), options: { temperature: None, top_p: None, max_steps: Some(40), max_tokens: None } }
  ag.with_permission_gate(base, rules.refactor_permission())
}

