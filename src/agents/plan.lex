import "lex-llm/agent" as ag

import "lex-llm/provider" as prov

import "lex-llm/providers" as providers

import "../tools/index" as tools

import "../permissions/rules" as rules

import "../prompts/plan" as pp

fn agent() -> [env] ag.AgentLoop {
  let base := { name: "plan", goal: pp.system(), model: prov.claude_sonnet(), provider: providers.anthropic(), tools: tools.tools_for_spec(rules.plan_permission()), options: { temperature: None, top_p: None, max_steps: Some(30), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.plan_permission())
}

fn mistral_agent() -> [env] ag.AgentLoop {
  let base := { name: "plan", goal: pp.system(), model: prov.mistral_large(), provider: providers.mistral(), tools: tools.tools_for_spec(rules.plan_permission()), options: { temperature: None, top_p: None, max_steps: Some(30), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.plan_permission())
}

fn ollama_agent() -> [env] ag.AgentLoop {
  let base := { name: "plan", goal: pp.system(), model: prov.ollama(providers.ollama_model()), provider: providers.ollama_local(), tools: tools.plan_dynamic_tools(), options: { temperature: None, top_p: None, max_steps: Some(20), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.plan_permission())
}

fn litellm_agent() -> [env] ag.AgentLoop {
  let base := { name: "plan", goal: pp.system(), model: prov.make_model_ref("litellm", tools.litellm_model()), provider: providers.litellm(), tools: tools.plan_dynamic_tools(), options: { temperature: None, top_p: None, max_steps: Some(20), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.plan_permission())
}

fn vllm_agent() -> [env] ag.AgentLoop {
  let base := { name: "plan", goal: pp.system(), model: prov.vllm(providers.vllm_model()), provider: providers.vllm_local(), tools: tools.tools_for_spec(rules.plan_permission()), options: { temperature: None, top_p: None, max_steps: Some(30), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.plan_permission())
}

fn openai_agent() -> [env] ag.AgentLoop {
  let base := { name: "plan", goal: pp.system(), model: prov.gpt4o(), provider: providers.openai(), tools: tools.tools_for_spec(rules.plan_permission()), options: { temperature: None, top_p: None, max_steps: Some(30), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.plan_permission())
}

fn google_agent() -> [env] ag.AgentLoop {
  let base := { name: "plan", goal: pp.system(), model: prov.gemini_pro(), provider: providers.google(), tools: tools.tools_for_spec(rules.plan_permission()), options: { temperature: None, top_p: None, max_steps: Some(30), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.plan_permission())
}

fn opencode_agent() -> [env] ag.AgentLoop {
  let base := { name: "plan", goal: pp.system(), model: prov.make_model_ref("opencode", tools.opencode_model()), provider: providers.opencode_go(), tools: tools.tools_for_spec(rules.plan_permission()), options: { temperature: None, top_p: None, max_steps: Some(30), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.plan_permission())
}

