---
status: accepted
date: 2026-10-21
decision-makers: [maintainers]
---

# 0016. Follow the family's GitHub work conventions, with low-risk PRs merging themselves

## Context and Problem Statement

Green PRs were waiting on the owner, most of them knowledge base pages that only needed a skim.
The family adopted conventions for GitHub work in all of the owner's repos: fewer, larger PRs, a
batch review for most of them, the owner acting from chat, and a fixed class of low-risk PRs that
merge themselves on green. How does this repo take them up without letting code, infrastructure or
pipeline changes merge unread?

## Considered Options

- Adopt the conventions with the default low-risk set: only the knowledge base
- Adopt them with a wider set (all of `docs/`, `README.md`)
- Keep merging every PR by hand

## Decision Outcome

Chosen option: "Adopt the conventions with the default low-risk set", because this repo deploys
infrastructure, and a wrong word in a deployment guide under `stratusphere/docs/` or `docs/` can
send an operator down the wrong path. Only `docs/knowledge/**` and `llms.txt` qualify.

Also recorded in: [ai-brain 0014](https://github.com/nickprignano/ai-brain/blob/main/docs/knowledge/decisions/0014-family-format-auto-merge-low-risk-prs.md),
the source of truth for what counts as low-risk, how the workflow decides and how to stop it.

For this repo:

- **Copied from the hub unchanged:** `.github/workflows/kb-auto-merge.yml` and
  `scripts/kb/auto_merge.py`. The script's fixed deny list keeps decisions, `kb.toml`, workflows,
  scripts, agent instructions and anything that looks like code out of the low-risk class, whatever
  `auto_merge_paths` says.
- **Settings in `kb.toml`:** `auto_merge = "off"` and
  `auto_merge_paths = ["docs/knowledge/**", "llms.txt"]`. A second, small PR sets it to `"on"`
  once the owner has done the repo settings.
- **`kb-validate` runs on every PR**, not only on KB paths, so it can be a required check.
- **Required checks** in the branch ruleset are the ones that run on every PR here: `auto-merge`,
  `validate` (kb-validate), `gitleaks` (secrets) and `kb-capture`. Never `tier` or `stratusphere`,
  which only run when their paths change, so a required one would hold every other PR.
- **Sessions never arm auto-merge or approve the owner's PRs.** The workflow is the only route, and
  anyone can keep a PR for the owner with the `no-auto-merge` label. The `AGENTS.md` line says so.

### Consequences

- Good, because KB pages land on green without the owner, and the owner's review goes to code,
  Bicep and decisions.
- Good, because the class is decided from the base branch by a fixed list, not by the thread that
  wrote the PR.
- Bad, because a wrong fact on a KB page can land without a human read. Validation, leak patterns
  and gitleaks still run first, and freshness and feedback catch errors afterward.
- Bad, because `kb-validate` now runs on PRs that change only Bicep or PowerShell, about a minute
  each.

## More Information

Adopted through handoff avd-liquidware#16 ([0015](0015-family-format-handoff-issues.md)), approved
by the owner on 2026-10-19. The first real PR should confirm that the `auto-merge` check attaches to
the PR's head commit, as the hub asks.
