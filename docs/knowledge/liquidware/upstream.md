---
title: "Asks for Liquidware"
summary: "Gaps found while automating Stratusphere in Azure, with the evidence, to raise with Liquidware"
topic: liquidware
status: partial
last_reviewed: 2026-10-18
---

# Asks for Liquidware

Gaps this project has hit, worth raising with Liquidware. Each says what's missing, the evidence,
and its status. *(The family keeps these in an `upstream.yaml` data file; this KB can't yet, because
the shared scripts read that file from a fixed path. A family format proposal is open:
[decision 0012](../decisions/0012-family-format-upstream-path-in-kb-toml.md).)*

| Ask | Evidence | Status |
|---|---|---|
| Configure a new Hub through the API (license, API user, allow list) so first-time setup can be automated | The published API guide covers data queries only ([api.md](../stratusphere/api.md)); whether the Hub's own reference shows configuration calls is *unverified* | Open, to check on the first lab run |
| Publish the Database and Collector roles in Azure Marketplace, or document how to deploy them in Azure | The Marketplace offer is documented for the Hub; Database and Collector plans are *unverified* | Open |
| A sample that keeps TLS verification on | The SE PowerTools batch script disables certificate checks ([community-projects.md](community-projects.md)) | Open |
| A license on the liquidwarelabs sample repos, so the community can adapt them | No license file ([community-projects.md](community-projects.md)) | Open |
| Document the Connector ID Key's exit codes, service names and settings key for scripted rollouts | This KB marks them *unverified* ([connector-id-key.md](../stratusphere/connector-id-key.md)) | Open |
