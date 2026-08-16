import "lex-llm/agent" as ag

import "lex-llm/provider" as prov

import "lex-llm/providers" as providers

import "lex-llm/providers/vertex" as vtx

import "../tools/index" as tools

import "../permissions/rules" as rules

import "../prompts/build" as bp

import "../prompts/build_ollama" as bpo

import "std.list" as list

fn agent() -> [env] ag.AgentLoop {
  let base := { name: "build", goal: bpo.system(), model: prov.claude_sonnet(), provider: providers.anthropic(), tools: tools.all_tools(), options: { temperature: None, top_p: None, max_steps: Some(50), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.build_permission())
}

fn openai_agent() -> [env] ag.AgentLoop {
  let base := { name: "build", goal: bpo.system(), model: prov.gpt4o(), provider: providers.openai(), tools: tools.all_tools(), options: { temperature: None, top_p: None, max_steps: Some(50), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.build_permission())
}

fn mistral_agent() -> [env] ag.AgentLoop {
  let base := { name: "build", goal: bpo.system(), model: prov.mistral_large(), provider: providers.mistral(), tools: tools.all_tools(), options: { temperature: None, top_p: None, max_steps: Some(50), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.build_permission())
}

fn ollama_agent() -> [env] ag.AgentLoop {
  let base := { name: "build", goal: bpo.system(), model: prov.ollama(providers.ollama_model()), provider: providers.ollama_local(), tools: tools.minimal_tools(), options: { temperature: None, top_p: None, max_steps: Some(20), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.build_permission())
}

fn litellm_agent() -> [env] ag.AgentLoop {
  let base := { name: "build", goal: bpo.system(), model: prov.make_model_ref("litellm", tools.litellm_model()), provider: providers.litellm(), tools: tools.dynamic_tools(), options: { temperature: None, top_p: None, max_steps: Some(20), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.build_permission())
}

fn vllm_agent() -> [env] ag.AgentLoop {
  let base := { name: "build", goal: bp.system(), model: prov.vllm(providers.vllm_model()), provider: providers.vllm_local(), tools: tools.all_tools(), options: { temperature: None, top_p: None, max_steps: Some(50), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.build_permission())
}

fn google_agent() -> [env] ag.AgentLoop {
  let base := { name: "build", goal: bpo.system(), model: prov.gemini_pro(), provider: providers.google(), tools: tools.all_tools(), options: { temperature: None, top_p: None, max_steps: Some(50), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.build_permission())
}

# OpenCode Go plan (https://opencode.ai/docs/zen) — an OpenAI-compatible
# endpoint over full-scale cloud models (DeepSeek, Qwen3, Kimi, GLM, MiniMax,
# MiMo), not a small local model, so it gets the same full tool budget as the
# other cloud providers above rather than litellm/ollama's stripped-down
# treatment. OPENCODE_API_KEY required; OPENCODE_MODEL overrides the default.
fn opencode_agent() -> [env] ag.AgentLoop {
  let base := { name: "build", goal: bpo.system(), model: prov.make_model_ref("opencode", tools.opencode_model()), provider: providers.opencode_go(), tools: tools.all_tools(), options: { temperature: None, top_p: None, max_steps: Some(50), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.build_permission())
}

fn vertex_agent() -> [env] ag.AgentLoop {
  let base := { name: "build", goal: bpo.system(), model: vtx.gemini_35_flash(), provider: providers.vertex(), tools: tools.all_tools(), options: { temperature: None, top_p: None, max_steps: Some(50), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.build_permission())
}

