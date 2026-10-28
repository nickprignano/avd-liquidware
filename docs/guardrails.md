# Guardrails

The rules every change to `avd-liquidware` follows, whoever makes it: a person, a workflow or an AI assistant. CI enforces the ones it can (marked **CI**). Reviewers check the rest.

## 1. Nothing public identifies a real account or project (**CI**: gitleaks)

The repo is public. Never commit:

- API keys, tokens, tenant, subscription, object, client or resource IDs, account, org or workspace IDs
- state files, assessment exports, or user and machine names from a real environment
- domains, emails, hostnames, real IP ranges
- employer, customer or private-project names

Use placeholders such as `<tenant-id>`, `<subscription-id>`, `contoso.com` and `10.x`.

## 2. Secrets never pass through chat or the repo

Keys live in Key Vault or environment variables. Scripts never print them. A chat assistant never asks for, shows or stores a secret; the user runs the step that handles it (`Set-LiquidwareSecret.ps1`).

## 3. Every change through a PR; nothing touches a real account without a yes

Changes land through pull requests with green CI. Nothing changes a real account, deployment, spend limit or key without the owner's explicit yes and cost estimate.

## 4. Respect licenses: no vendor binaries

No Liquidware binaries, installers or license material go in the repo. Installers are uploaded by the operator to their own Entra-only media storage account (`Publish-LiquidwareMedia.ps1`).

## 5. Knowledge lives in liquidware-ninja

Shared Liquidware knowledge, gotchas, known errors, and family decisions live in [liquidware-ninja](https://github.com/nickprignano/liquidware-ninja/tree/main/docs/knowledge). Architecture decisions specific to this repository's deployment design live in [docs/decisions/](decisions/README.md).
