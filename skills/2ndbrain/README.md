# 2ndbrain: closeout, capture and sync for a second brain

A Claude skill that closes out a thread by capturing what it produced into the right place: the
**project's own KB**, the **public hub KB** (this repo's format), or a **private layer** (a
personal notes vault). It refuses anything that's unsafe for the public side, and it also syncs
family projects through the hub. The skill itself is [SKILL.md](SKILL.md).

## Why three places

What's true about one project's product belongs next to that project's code. What every project
shares belongs in the hub. Judgment, goals and disagreements are personal, so they belong in a
private repo. One entry point that routes between them means the person capturing doesn't have to
decide, and every public destination gets the same safety gate.

## Closeout: the thread's last step

At the end of a thread the skill offers a closeout in one line, or runs it when asked ("close
out"). It always takes the same six steps:

1. **Review** the thread for lessons, decisions, root causes (only after troubleshooting),
   procedures (only when steps were asked for), patterns, disagreements (only when asked) and open
   loops.
2. **Route** each one.
3. **Propose** one numbered batch, with destinations, and ask for one yes ("yes except 3").
4. **Write** what's approved: one PR per public KB, one commit to the private layer.
5. **Record** where each item went.
6. **List the open loops** and who owes the next step.

## How it routes

```
                       ┌─ about this project's product ──▶ project KB (PR) ─┐
 thread ──▶ closeout ──┼─ shared, or AI tooling ─────────▶ hub KB (PR) ◀─────┘ weekly digest
                       ├─ personal ──────────────────────▶ private layer (direct) ◀── hub roll-up
                       └─ secrets, customer or tenant specifics ──▶ refused
```

- **Project KB:** found from the session's repo (`family.yaml` row with `self: true`) or the hub's
  `family.yaml`. Gets facts, known errors and decisions about that project's product.
- **Another project's KB:** only by PR and only when the user says yes in the batch.
- **Hub:** what several projects share, and the AI tooling and conventions it owns.
- **Private layer:** decisions, goals, disagreements and personal lessons, committed directly.
  Work material never goes there, even generalised.
- **One home per fact:** the KB whose `owns` covers it holds it; the others link to it. The
  user's own takeaway goes to the private layer, linking out.
- **Up, never sideways:** project KBs reach the hub through its digest, and the hub reaches the
  private layer through its roll-up, so nothing public is also copied into the private layer.
- **Refused:** secrets of any kind, and customer, tenant or employer specifics. What's true about
  the product in general can still go to the project KB, rewritten to be generic.

Before anything reaches a public KB it passes that repo's [guardrails](../../docs/guardrails.md):
no IDs, domains, emails, IPs, private app names or user data. A draft that can be generalised is
rewritten and shown in the batch; one that can't is dropped, or goes to the private layer if it's
personal and not work material.

## The one setting that matters: `private_layer`

| | `hidden` (default) | `named` |
|---|---|---|
| Public text | Never mentions the private layer. | May say a private layer exists, reads the hub and is never linked from it. |
| Split captures | Two independent notes; the hub PR says nothing about the other half. | The hub PR may say the personal takeaway was filed privately. |
| Always private | Contents, note names, paths, links, reasoning. | The same. |
| Before switching | Nothing. | A hub decision record allowing it, since guardrails change only by decision. |

## Sync: the hub as the channel between projects

Claude projects can't read each other's chats, so a family project learns what changed elsewhere
from the hub. At the start of work in a family project (or on "2ndbrain sync"), the skill reads
the hub's public `directives.yaml`, `decisions/` and `family.yaml`, and reports:

- the directives in scope for this project, quoted exactly, with any pause;
- the decisions added or changed since the last sync, flagging family-format ones not yet adopted;
- whether this project's format version matches the hub's.

On request it writes a **handoff block**: one self-contained Markdown block, dated and pinned to
a hub commit, that a person pastes into another project. It's built only from public hub files,
so it never carries chat content, private-layer material or secrets.

Sync only reads. It writes nothing to any repo; adoption PRs it points to go through the normal
flow with the user's yes. Directives follow
[decision 0008](../../docs/knowledge/decisions/0008-family-format-maintainer-directives-and-pause-switch.md)
(proposed) and never override the guardrails or the user's own word.

## Install

1. Copy [SKILL.md](SKILL.md) into a new skill in your Claude account. It's meant to work in every
   session, so an account skill fits better than a project one. Inside a KB repo it sits alongside
   that repo's `2ndbrain-kb` skill (`.claude/skills/2ndbrain-kb/`), which covers working on the KB
   itself.
2. Fill in the settings block: your hub repo, `project_kb` (leave it on `auto`), your private
   repo, its capture-rules file, `private_layer`, and the two sync settings.
3. Give your sessions push access to the repos you capture into, or use it from a plain chat,
   where it drafts notes for you to file.
4. Turn off any older capture skill that covers the same triggers, so only one fires.

## Not in v1

Searching or answering from any KB or the private layer, the private layer's roll-up and patterns, writing
directives (sync only reads them), and staleness reviews.
