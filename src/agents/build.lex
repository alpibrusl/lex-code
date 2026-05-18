import "lex-llm/agent"    as ag
import "lex-llm/provider" as prov

import "../tools/index"   as tools
import "../prompts/build" as bp

fn agent() -> ag.AgentDef {
  { name:     "build",
    goal:     bp.system(),
    model:    prov.claude_sonnet(),
    provider: prov.anthropic(),
    tools:    tools.all_tools(),
    options:  { temperature: None, top_p: None, max_steps: Some(50), max_tokens: None } }
}
