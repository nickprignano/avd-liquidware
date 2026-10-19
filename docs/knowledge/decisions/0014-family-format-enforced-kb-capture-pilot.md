---
status: accepted
date: 2026-10-19
decision-makers: [maintainers]
---

# 0014. Pilot the family's enforced knowledge capture, in warn mode

## Context and Problem Statement

The family accepted a rule that knowledge capture is enforced, not just asked for: a thread
closeout on the Claude side, a Claude Code Stop hook in each repo, and a `kb-capture` PR check with
a `no-kb` opt-out. This KB is one of the pilot repos, next to the AVD repos and the Nerdio HCL kit.
How does this repo run the pilot without slowing work that has a fixed date?

## Considered Options

- Join the pilot in warn mode: the hook only reminds, the PR check runs for real
- Join the pilot in block mode
- Stay out of the pilot

## Decision Outcome

Chosen option: "Join the pilot in warn mode", because the family runs every KB that already has CI
in warn mode first, and the PR check still makes "nothing to capture" an explicit choice.

Also recorded in: [ai-brain 0011](https://github.com/nickprignano/ai-brain/blob/main/docs/knowledge/decisions/0011-family-format-enforced-kb-capture.md),
the source of truth for how the closeout, the hook and the check work.

For this repo:

- **Installed from the family's template export**, not by hand: `scripts/kb/capture_check.py`, the
  `kb-capture` workflow and the Stop hook in `.claude/settings.json`. The family scripts stay
  identical to the export's; only `kb.toml` differs.
- **Warn mode:** `capture_hook = "warn"` in `kb.toml`. The Stop hook posts a reminder and never
  blocks.
- **The PR check runs for real.** A PR that changes code without changing `docs/knowledge/` needs
  the `no-kb` label and a `No KB entry: <reason>` line in its body. The family's own automation PRs
  are exempt.
- **Fixed-date work doesn't wait.** A demo PR that goes red takes `no-kb` and a reason instead of
  waiting on a KB entry.
- **The project's private repo is exempt** from the hook and the check for the pilot. Its threads
  still run the closeout, and a lesson from it reaches this KB only after a guardrail check. It is
  named only in the project's own instructions, never here.
- **Thread closeout.** Every thread in this repo's Claude project runs the 2ndbrain closeout before
  its final reply, and the project's coordinator doesn't resolve a thread until the closeout is
  recorded or the owner waives it. Private-layer writes still wait for the owner's yes.
- **Pilot dates:** through 2026-10-31, counted from when the hook and the check go live, with a
  review on 2026-11-01. At each checkpoint the project adds one field report to the AI KB: PRs
  merged, how many carried a KB change, how many used `no-kb`, and how often the hook warned.

### Consequences

- Good, because lessons from code changes are asked for every time, by the harness and by CI.
- Good, because a `no-kb` reason makes a skipped entry visible and reviewable.
- Bad, because the hook runs only in Claude Code sessions, and a person can still merge past a red
  check.
- Neutral, because warn mode can move to block after the review, by changing one setting.

## More Information

Asked for in a handoff issue from the AI project (avd-liquidware#12), approved by the owner on
2026-10-19. The review on 2026-11-01 decides whether this repo stays in warn mode or moves to block.
