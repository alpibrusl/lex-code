import "lex-llm/agent"    as ag
import "lex-llm/provider" as prov

import "../tools/index"  as tools
import "../prompts/plan" as pp

fn agent() -> ag.AgentDef {
  { name:     "plan",
    goal:     pp.system(),
    model:    prov.claude_sonnet(),
    provider: prov.anthropic(),
    tools:    tools.read_only_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(30), max_tokens: None } }
}
