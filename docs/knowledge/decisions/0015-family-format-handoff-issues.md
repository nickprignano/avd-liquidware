---
status: accepted
date: 2026-10-19
decision-makers: [maintainers]
---

# 0015. Take handoffs from other Claude projects as `handoff` issues

## Context and Problem Statement

Work that starts in another of the owner's Claude projects, such as a family decision this KB has
to adopt, used to arrive as a prompt the owner pasted by hand. The family now hands work over as an
issue in the receiving repo. How does this repo receive handoffs and report back?

## Considered Options

- Take handoffs as `handoff` issues, as the family decided
- Keep receiving pasted prompts

## Decision Outcome

Chosen option: "Take handoffs as `handoff` issues", because the issue carries the whole ask, what it
waits on and the report back, and the owner's approval stays one visible act: the `handoff` label.

Also recorded in: [ai-brain 0012](https://github.com/nickprignano/ai-brain/blob/main/docs/knowledge/decisions/0012-family-format-handoff-issues.md),
the source of truth for the issue's shape, approval, pickup and report back.

For this repo:

- **Installed from the family's template export:** the handoff issue template, the
  `scripts/kb/handoffs.py` script, the `SessionStart` hook in `.claude/settings.json` that lists
  open handoff issues at the start of every session, the `AGENTS.md` line, and the `handoff` and
  `handoff-proposed` labels, which `kb-freshness` creates.
- **Only the owner makes a handoff live,** by adding the `handoff` label. Claude never adds it.
- **A daily routine** in the Liquidware Claude project lists this repo's open `handoff` issues, for
  days no session opens the repo. It comments once when a handoff is still waiting and stays quiet
  until that changes.
- **Report back:** the receiving thread comments its PR links on the issue and closes it once the
  PRs are open. Merging stays the owner's.

### Consequences

- Good, because handoffs no longer depend on the owner pasting prompts and remembering what waits
  on what.
- Bad, because the daily routine costs a run even on days with nothing to do.

## More Information

First use: avd-liquidware#12, which adopted [0014](0014-family-format-enforced-kb-capture-pilot.md)
and this decision.
