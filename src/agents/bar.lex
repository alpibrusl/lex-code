# BAR mode — walk a project against the minimum bar.
#
# Same shape as agents/review.lex, with two deliberate differences: the
# toolset is review's minus nothing and plus bar_check, and the local
# providers keep their tools instead of being degraded to none. Review
# can still say something useful with no tools; a bar walk with no
# bar_check is a model reciting a checklist from memory, which is the
# failure mode this mode exists to replace.

import "lex-llm/agent" as ag

import "lex-llm/provider" as prov

import "lex-llm/providers" as providers

import "lex-llm/providers/vertex" as vtx

import "../tools/index" as tools

import "../permissions/rules" as rules

import "../prompts/bar" as barp

fn agent() -> [env] ag.AgentLoop {
  let base := { name: "bar", goal: barp.system(), model: prov.claude_sonnet(), provider: providers.anthropic(), tools: tools.bar_tools(), options: { temperature: None, top_p: None, max_steps: Some(25), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.bar_permission())
}

fn openai_agent() -> [env] ag.AgentLoop {
  let base := { name: "bar", goal: barp.system(), model: prov.gpt4o(), provider: providers.openai(), tools: tools.bar_tools(), options: { temperature: None, top_p: None, max_steps: Some(25), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.bar_permission())
}

fn mistral_agent() -> [env] ag.AgentLoop {
  let base := { name: "bar", goal: barp.system(), model: prov.mistral_large(), provider: providers.mistral(), tools: tools.bar_tools(), options: { temperature: None, top_p: None, max_steps: Some(25), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.bar_permission())
}

fn google_agent() -> [env] ag.AgentLoop {
  let base := { name: "bar", goal: barp.system(), model: prov.gemini_pro(), provider: providers.google(), tools: tools.bar_tools(), options: { temperature: None, top_p: None, max_steps: Some(25), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.bar_permission())
}

fn ollama_agent() -> [env] ag.AgentLoop {
  let base := { name: "bar", goal: barp.system(), model: prov.ollama(providers.ollama_model()), provider: providers.ollama_local(), tools: tools.bar_tools(), options: { temperature: None, top_p: None, max_steps: Some(12), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.bar_permission())
}

fn litellm_agent() -> [env] ag.AgentLoop {
  let base := { name: "bar", goal: barp.system(), model: prov.make_model_ref("litellm", tools.litellm_model()), provider: providers.litellm(), tools: tools.bar_tools(), options: { temperature: None, top_p: None, max_steps: Some(12), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.bar_permission())
}

fn vllm_agent() -> [env] ag.AgentLoop {
  let base := { name: "bar", goal: barp.system(), model: prov.vllm(providers.vllm_model()), provider: providers.vllm_local(), tools: tools.bar_tools(), options: { temperature: None, top_p: None, max_steps: Some(25), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.bar_permission())
}

fn opencode_agent() -> [env] ag.AgentLoop {
  let base := { name: "bar", goal: barp.system(), model: prov.make_model_ref("opencode", tools.opencode_model()), provider: providers.opencode_go(), tools: tools.bar_tools(), options: { temperature: None, top_p: None, max_steps: Some(25), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.bar_permission())
}

fn vertex_agent() -> [env] ag.AgentLoop {
  let base := { name: "bar", goal: barp.system(), model: vtx.gemini_35_flash(), provider: providers.vertex(), tools: tools.bar_tools(), options: { temperature: None, top_p: None, max_steps: Some(25), max_tokens: None }, permission_spec: None }
  ag.with_permission_gate(base, rules.bar_permission())
}

