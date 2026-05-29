import "lex-llm/agent" as ag

import "lex-llm/provider" as prov

import "lex-llm/providers" as providers

import "../tools/index" as tools

import "../permissions/rules" as rules

import "../prompts/review" as rvp

fn agent() -> [env] ag.AgentDef {
  let base := { name: "review", goal: rvp.system(), model: prov.claude_sonnet(), provider: providers.anthropic(), tools: tools.tools_for_spec(rules.review_permission()), options: { temperature: None, top_p: None, max_steps: Some(25), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.review_permission())
}

fn mistral_agent() -> [env] ag.AgentDef {
  let base := { name: "review", goal: rvp.system(), model: prov.mistral_large(), provider: providers.mistral(), tools: tools.tools_for_spec(rules.review_permission()), options: { temperature: None, top_p: None, max_steps: Some(25), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.review_permission())
}

fn ollama_agent() -> [env] ag.AgentDef {
  let base := { name: "review", goal: rvp.system(), model: prov.ollama(providers.ollama_model()), provider: providers.ollama_local(), tools: tools.tools_for_spec(rules.review_permission()), options: { temperature: None, top_p: None, max_steps: Some(25), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.review_permission())
}

fn vllm_agent() -> [env] ag.AgentDef {
  let base := { name: "review", goal: rvp.system(), model: prov.vllm(providers.vllm_model()), provider: providers.vllm_local(), tools: tools.tools_for_spec(rules.review_permission()), options: { temperature: None, top_p: None, max_steps: Some(25), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.review_permission())
}

fn openai_agent() -> [env] ag.AgentDef {
  let base := { name: "review", goal: rvp.system(), model: prov.gpt4o(), provider: providers.openai(), tools: tools.tools_for_spec(rules.review_permission()), options: { temperature: None, top_p: None, max_steps: Some(25), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.review_permission())
}

fn google_agent() -> [env] ag.AgentDef {
  let base := { name: "review", goal: rvp.system(), model: prov.gemini_pro(), provider: providers.google(), tools: tools.tools_for_spec(rules.review_permission()), options: { temperature: None, top_p: None, max_steps: Some(25), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.review_permission())
}

