# Guardrails

The rules every change to this knowledge base follows, whoever makes it: a person, a workflow or an
AI assistant. They're the same in every KB of the family ([family.yaml](knowledge/family.yaml)),
worded for this one's topic. CI enforces the ones it can (marked **CI**). Reviewers check the rest.

## 1. Nothing public identifies a real account or project (**CI**: gitleaks, validate.py)

The repo is public. Never commit:

- API keys, tokens, tenant, subscription, object, client or resource IDs, account, org or
  workspace IDs
- state files, assessment exports, or user and machine names from a real environment
- domains, emails, hostnames, real IP ranges
- prompts, transcripts or data from a private app or a real user
- employer, customer or private-project names

Write lessons as general advice ("in a personal app with per-user budgets"), not as a story about
a specific one. Use placeholders such as `<tenant-id>`, `<subscription-id>`, `contoso.com` and `10.x`.
Published identifiers that are the same for everyone, such as model IDs and API versions, are fine.

## 2. Secrets never pass through chat, the repo or the KB

Keys live in the platform's secret store or environment variables. Scripts never print them. A chat
assistant never asks for, shows or stores a secret; the user runs the step that handles it.

## 3. Every change through a PR; nothing touches a real account without a yes

Changes land through pull requests with green CI. Nothing changes a real account, deployment,
spend limit or key without the owner's explicit yes.

## 4. Respect licenses: unlicensed code is reference only

Code from repos with no license is reference only. Use facts from it, cite the source, and never
copy, adapt, fork or redistribute it. Check the license of every vendor repo or sample before using
it. This repo is MIT, and the knowledge base tooling it adapts from the family keeps Apache-2.0
([LICENSE-APACHE](../LICENSE-APACHE)); [NOTICE](../NOTICE) says which paths each covers. No Liquidware
binaries, installers or license material go in the repo.

## 5. Free and open first; paid services need a decision

Prefer Azure-native, GitHub, HashiCorp and open-source tooling. A paid third-party service needs a decision
record saying why the free options fell short. The KB's own tooling calls no paid service.

## 6. Works from a browser

Every step works from a browser, on an iPad included: GitHub's web UI and Actions, or Azure
Cloud Shell. No local installs required.

## 7. Every decision and lesson goes into the KB

Decisions get a record in [decisions/](knowledge/decisions/README.md), lessons go on the topic page
they belong to, and these guardrails stay visible here, in [AGENTS.md](../AGENTS.md) and in the
[README](../README.md).

## When a guardrail gets in the way

Don't work around it quietly. Open an issue or a decision record that says which guardrail, why,
and what the safer alternative is. A guardrail changes only by a new decision record, and a change
to the shared rules is a family format change ([curation.md](knowledge/curation.md#staying-aligned-with-the-family)).
