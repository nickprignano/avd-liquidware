# Decision records

Short records of choices that shape this knowledge base and the work it covers. One file per
decision, numbered in order, in [MADR 4](https://adr.github.io/madr/) format. Copy
[template.md](template.md) to add one. A decision stays `proposed` until the maintainer says yes.
A reversed decision gets a new record, and the old one is marked *Superseded by NNNN*. Each KB in
the family numbers its own decisions; refer to a sibling's as `<project> 0012`, with a link.

<!-- BEGIN GENERATED: decision-index (from front matter; run scripts/kb/build.py) -->
| # | Decision | Status |
|---|---|---|
| [0001](0001-adopt-the-2ndbrain-format.md) | Adopt the 2ndbrain knowledge base format, version 1 | Accepted |
| [0002](0002-mit-license-apache-kb-tooling.md) | MIT for the repo; the knowledge base tooling keeps Apache-2.0 | Accepted |
| [0003](0003-deploy-here-assess-and-design-elsewhere.md) | This repo deploys the Liquidware platform; assessment and design live elsewhere | Proposed |
| [0004](0004-marketplace-appliances-no-vendor-binaries.md) | Deploy appliances from Azure Marketplace; no Liquidware binaries or license material in the repo | Proposed |
| [0005](0005-bicep-with-azure-verified-modules.md) | Bicep with pinned Azure Verified Modules, following avd-landing-zone | Proposed |
| [0006](0006-credentials-in-key-vault.md) | Generated credentials go to Key Vault, and reruns reuse them | Proposed |
| [0007](0007-real-runs-are-the-source-of-truth.md) | Real runs are the source of truth; every lesson adds a guard | Proposed |
| [0008](0008-cloud-shell-baseline.md) | Everything runs from Azure Cloud Shell | Proposed |
| [0009](0009-unlicensed-code-reference-only.md) | Unlicensed code is reference only | Proposed |
| [0010](0010-prefer-azure-github-hashicorp-oss.md) | Prefer Azure-native, GitHub, HashiCorp and open-source tooling | Proposed |
| [0011](0011-family-format-guard-on-known-errors.md) | Family format: a guard field on known errors | Proposed |
| [0012](0012-family-format-upstream-path-in-kb-toml.md) | Family format: the upstream asks file's path set in kb.toml | Proposed |
| [0013](0013-family-model-selection-convention.md) | Follow the family's model-selection convention | Proposed |
| [0014](0014-family-format-enforced-kb-capture-pilot.md) | Pilot the family's enforced knowledge capture, in warn mode | Accepted |
| [0015](0015-family-format-handoff-issues.md) | Take handoffs from other Claude projects as `handoff` issues | Accepted |
<!-- END GENERATED: decision-index -->
