---
title: "Liquidware products and where they're documented"
summary: "Which Liquidware products this KB covers, and where Liquidware publishes docs, support articles and news"
topic: liquidware
status: verified
last_reviewed: 2026-10-19
---

# Liquidware products and where they're documented

This KB covers the Liquidware products this repo deploys: Stratusphere UX for assessments, and
ProfileUnity, FlexApp and CommandCTRL as an optional tier for Azure Virtual Desktop. How they fit
with AVD and FSLogix is on [avd/fit-with-avd-and-fslogix.md](../avd/fit-with-avd-and-fslogix.md).

| Product | What it does | Covered here |
|---|---|---|
| Stratusphere UX | Monitoring and assessment of desktop user experience: Hub and optional Database and Collector appliances, plus the Connector ID Key agent | Yes: [stratusphere/](../stratusphere/appliances.md) |
| ProfileUnity | User environment and profile management | Yes: [avd/](../avd/fit-with-avd-and-fslogix.md) |
| FlexApp | Application layering and delivery | Yes: [avd/](../avd/fit-with-avd-and-fslogix.md) |
| CommandCTRL | Real-time endpoint monitoring and remote support | Yes: [avd/](../avd/fit-with-avd-and-fslogix.md) |

## Where Liquidware publishes

- **Product documentation:** [docs.liquidware.com](https://docs.liquidware.com). The site renders in
  the browser and has no feed, so the curator can't watch it; check it by hand when a page here
  depends on it.
- **Release notes:** published per product and version in the documentation site and as
  "Product Releases" articles in the support center, which the curator watches.
- **Support center:** [support.liquidware.com](https://support.liquidware.com), a Zendesk help
  center covering every product, with Stratusphere sections for administration, usage and upgrade
  troubleshooting. The curator watches it through Zendesk's article API. The HTML site blocks
  automated requests; the API doesn't.
- **News and blog:** the RSS feed at `https://www.liquidware.com/rss.xml`, watched by the curator.
  The usual `/feed` paths return 404.
- **Azure Marketplace:** the `liquidware` publisher's `stratusphere` offer
  ([azure/marketplace.md](../azure/marketplace.md)). No feed; check by hand.
- **GitHub:** the [liquidwarelabs](https://github.com/liquidwarelabs) organization
  ([community-projects.md](community-projects.md)).

Checked 2026-10-18.
