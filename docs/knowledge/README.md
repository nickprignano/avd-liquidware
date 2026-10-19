---
title: "Knowledge base"
summary: "What this knowledge base is, how it's organised, and how to add to it safely"
topic: overview
status: partial
last_reviewed: 2026-10-18
---

# Knowledge base

What this project has learned: research findings, gotchas, fixes with versions, and the decisions
behind them. It's written for people, tools and LLM agents alike. When something new is learned,
add it to the topic page it belongs to instead of starting a new file.

## Index

<!-- BEGIN GENERATED: kb-index (from front matter; run scripts/kb/build.py) -->
| Page | What's in it | Status |
|---|---|---|
| [liquidware/community-projects.md](liquidware/community-projects.md) | Public code and tools around Stratusphere, with their licenses and what this project may reuse | verified |
| [liquidware/products.md](liquidware/products.md) | Which Liquidware products this KB covers, and where Liquidware publishes docs, support articles and news | verified |
| [liquidware/upstream.md](liquidware/upstream.md) | Gaps found while automating Stratusphere in Azure, with the evidence, to raise with Liquidware | partial |
| [avd/fit-with-avd-and-fslogix.md](avd/fit-with-avd-and-fslogix.md) | Which job each Liquidware product does next to AVD's own features and FSLogix: profiles, app delivery, support and assessment | partial |
| [stratusphere/api.md](stratusphere/api.md) | The Hub's read-only data API: the request shape, authentication, output formats and the built-in reference | partial |
| [stratusphere/appliances.md](stratusphere/appliances.md) | Hub, Database and Collector roles: when each is needed, sizes, addresses, credentials and what hasn't been confirmed on a real run | unverified |
| [stratusphere/connector-id-key.md](stratusphere/connector-id-key.md) | The Stratusphere agent on each desktop: installer switches, callbacks to the Hub, where its services and settings live, and images created later | partial |
| [stratusphere/hub-setup.md](stratusphere/hub-setup.md) | What has to be set in the Hub console after deployment (license, API user, API allow list) and what might move to the API | unverified |
| [azure/lab-costs.md](azure/lab-costs.md) | What keeps billing while a Stratusphere lab is stopped, and why a lab run ends torn down | partial |
| [azure/marketplace.md](azure/marketplace.md) | Liquidware's Marketplace offer: finding the plan for a region, the plan block a VM needs, and accepting terms per subscription | partial |
| [azure/networking.md](azure/networking.md) | The ports the appliances and Connector ID Keys need, egress without default outbound access, peering, and how routes affect callbacks | unverified |
| [deployment/gotchas.md](deployment/gotchas.md) | What trips up a Liquidware deployment in Azure, across products, with a link to where each is explained | partial |
| [troubleshooting/](troubleshooting/README.md) | Errors hit in this project: symptom, cause, fix and source | partial |
| [roadmap/](roadmap/README.md) | What this knowledge base plans to cover next | plan |
| [curation.md](curation.md) | How the KB stays current: the weekly digest, the prior-art check, the feedback loop, the freshness check and family alignment | verified |
| [experts.md](experts.md) | How we choose which people on this KB's topics the KB follows: the method, the scores and the list | verified |
| [decisions/](decisions/README.md) | Decision records (MADR): what was decided and why |  |
<!-- END GENERATED: kb-index -->

## Related knowledge bases

<!-- BEGIN GENERATED: family (from family.yaml; run scripts/kb/build.py) -->
| Knowledge base | Role | Focus | Source of truth for |
|---|---|---|---|
| [AI](https://github.com/nickprignano/ai-brain/tree/main/docs/knowledge) | reference | The AI research behind all four projects | Claude API and Microsoft Foundry use; model choices; keyless sign-in for AI APIs; prompts and evaluations; AI tooling shared by the family |
| [Nerdio HCL kit](https://github.com/nickprignano/nerdio-hcl/tree/main/docs/knowledge) | member | Nerdio Manager on Azure Virtual Desktop, deployed with Terraform and Packer | Nerdio Manager; the nerdio/nme provider; this kit's Terraform and Packer |
| [AVD](https://github.com/nickprignano/avd-second-brain/tree/main/knowledge) | member | Azure Virtual Desktop itself | Azure Virtual Desktop platform; FSLogix; session host images in general |
| Private layer (repo not linked yet) | observer | The maintainer's private wisdom layer. It reads the family through this hub and sends directives here as pull requests; its contents stay private | Directives to the family; through docs/knowledge/directives.yaml |
<!-- END GENERATED: family -->

When a fact belongs to a sibling's topic, link to their page instead of copying it. See
[curation.md](curation.md#staying-aligned-with-the-family).

## Before you build something

Every change follows the [guardrails](../guardrails.md). Run the prior-art check first
(`python3 scripts/kb/prior_art.py "<topic>"`, see
[curation.md](curation.md#prior-art-check-kb-prior-art)).

## How to add to it

- **Without editing files:** open a **Knowledge base feedback**, **Known error** or **Suggest an
  expert to follow** issue. When a maintainer labels it `kb-accepted`, a workflow turns it into a
  pull request.
- **With a pull request:** add a bullet to the matching topic page, say what happened, the fix and
  the versions it applies to, and mark anything you haven't confirmed as *unverified*. Known errors
  go in [troubleshooting/known-errors.yaml](troubleshooting/known-errors.yaml). Decisions are a copy
  of [decisions/template.md](decisions/template.md) at the next number, `proposed` until the
  maintainer says yes. Run `python3 scripts/kb/build.py` and `python3 scripts/kb/validate.py`
  before pushing.

## Format

Page front matter (`title`, `summary`, `topic`, `status`, `last_reviewed`) is checked against
[schema/page.schema.json](schema/page.schema.json). Decisions are
[MADR 4](https://adr.github.io/madr/) records. The YAML data files each have a JSON Schema in
[schema/](schema/page.schema.json), and the Markdown tables and `llms.txt` are generated from them.
The full system is in the [2ndbrain spec](../2ndbrain/SPEC.md).
