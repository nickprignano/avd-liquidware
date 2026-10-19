---
status: proposed
date: 2026-10-19
decision-makers: [maintainers]
---

# 0013. Follow the family's model-selection convention

## Context and Problem Statement

Work on this repo happens in Claude sessions: threads that write Bicep and PowerShell, research
Liquidware's products and keep this knowledge base. The family has one convention for which model
and effort each kind of Claude work uses, and model choices are the AI knowledge base's topic
([family.yaml](../family.yaml)). Does this repo follow it, and what does it change here?

## Considered Options

- Follow the convention, with any exception recorded here as a "Model override" decision
- Keep this repo's own model choices

## Decision Outcome

Chosen option: "Follow the convention", because this repo's work is the convention's thread case
(code, research, specs: Claude Opus 5.5 at `medium` effort), and nothing here needs an exception.

Also recorded in: [ai-brain 0006](https://github.com/nickprignano/ai-brain/blob/main/docs/knowledge/decisions/0006-model-selection-convention.md), the source of
truth for the defaults, when to raise effort, fallbacks and the pilot dates. The facts behind it are
on the AI KB's [Claude API page](https://github.com/nickprignano/ai-brain/blob/main/docs/knowledge/claude-api/README.md#choosing-a-model).

For this repo:

- Threads start on `claude-opus-5-5` at `medium` effort. The repo pins the same pair for Claude
  Code in `.claude/settings.json` (`model`, `effortLevel`), with a full model ID, never an alias.
- Effort goes up before the model changes: `high` for changes that touch secrets, identity or
  spend, which much of this repo's Bicep does.
- No code in this repo calls a model, so the convention's layers for apps and for Microsoft Foundry
  don't apply here.

### Consequences

- Good, because model choices for this repo follow evidence and the family's rules.
- Neutral, because no default changes today.

## More Information

Revisit at the family's pilot review on 2026-12-01.
