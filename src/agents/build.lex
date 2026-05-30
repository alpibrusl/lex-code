import "lex-llm/agent" as ag

import "lex-llm/provider" as prov

import "lex-llm/providers" as providers

import "../tools/index" as tools

import "../permissions/rules" as rules

import "../prompts/build" as bp

import "../prompts/build_ollama" as bpo

import "std.list" as list

fn agent() -> [env] ag.AgentDef {
  let base := { name: "build", goal: bpo.system(), model: prov.claude_sonnet(), provider: providers.anthropic(), tools: tools.all_tools(), options: { temperature: None, top_p: None, max_steps: Some(50), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.build_permission())
}

fn openai_agent() -> [env] ag.AgentDef {
  let base := { name: "build", goal: bpo.system(), model: prov.gpt55(), provider: providers.openai(), tools: tools.all_tools(), options: { temperature: None, top_p: None, max_steps: Some(50), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.build_permission())
}

fn mistral_agent() -> [env] ag.AgentDef {
  let base := { name: "build", goal: bpo.system(), model: prov.mistral_large(), provider: providers.mistral(), tools: tools.all_tools(), options: { temperature: None, top_p: None, max_steps: Some(50), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.build_permission())
}

fn ollama_agent() -> [env] ag.AgentDef {
  let base := { name: "build", goal: bpo.system(), model: prov.ollama(providers.ollama_model()), provider: providers.ollama_local(), tools: list.concat(tools.standard_tools(), tools.lex_cli_tools()), options: { temperature: None, top_p: None, max_steps: Some(10), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.build_permission())
}

fn vllm_agent() -> [env] ag.AgentDef {
  let base := { name: "build", goal: bp.system(), model: prov.vllm(providers.vllm_model()), provider: providers.vllm_local(), tools: tools.all_tools(), options: { temperature: None, top_p: None, max_steps: Some(50), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.build_permission())
}

fn google_agent() -> [env] ag.AgentDef {
  let base := { name: "build", goal: bpo.system(), model: prov.gemini_pro(), provider: providers.google(), tools: tools.all_tools(), options: { temperature: None, top_p: None, max_steps: Some(50), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.build_permission())
}

