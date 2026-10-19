# Model-selection pilot: session measures

This project follows the family's model-selection convention,
[ai-brain decision 0006](https://github.com/nickprignano/ai-brain/blob/main/docs/knowledge/decisions/0006-model-selection-convention.md),
as one of its pilot projects from 2026-10-18 to 2026-11-30, with the review on 2026-12-01. It has no
app that calls a model, so it tracks only the session measures that decision names.

| Measure | What counts |
|---|---|
| Bumps | A thread had to raise its effort (`high`, `xhigh`) or its model (Fable 5.1), or the user had to redo its work |
| Restarts | A session was restarted because quality slipped: it repeated a fixed mistake, forgot a stated constraint or contradicted an earlier decision |
| Cache share | The prompt-cache share Claude Code's `/usage` reports, noted at the end of a long session |

Add one row per event, as it happens. Name the thread by its topic only: no customer, employer,
tenant or private-project detail, here or in the report.

| Date | Measure | Thread topic | From, to | Why |
|---|---|---|---|---|

At the end of the pilot, the totals (threads, bumps, restarts, the cache shares) go to ai-brain as a
knowledge base feedback issue against its Claude API page.
