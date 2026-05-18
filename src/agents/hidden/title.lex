import "lex-llm/agent"    as ag
import "lex-llm/provider" as prov

fn agent() -> ag.AgentDef {
  { name:    "title",
    goal:    "Generate a short, descriptive title (5-8 words) for this coding session based on the conversation. Return only the title text, nothing else.",
    model:   prov.claude_sonnet(),
    provider: prov.anthropic(),
    tools:   [],
    options: { temperature: None, top_p: None, max_steps: Some(1), max_tokens: Some(20) } }
}
