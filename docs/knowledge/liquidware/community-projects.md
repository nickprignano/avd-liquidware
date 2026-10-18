---
title: "Prior art and community projects"
summary: "Public code and tools around Stratusphere, with their licenses and what this project may reuse"
topic: liquidware
status: verified
last_reviewed: 2026-10-18
---

# Prior art and community projects

What exists publicly around Stratusphere, checked before building anything here. Code without a
license is reference only: use facts from it and cite it, never copy it
([decision 0009](../decisions/0009-unlicensed-code-reference-only.md)).

| Project | What it is | License | Reuse |
|---|---|---|---|
| [liquidwarelabs/Stratusphere-UX](https://github.com/liquidwarelabs/Stratusphere-UX) | SE PowerTools, unsupported: a batch script that runs a CSV of API URLs into CSV files, sample API queries with inspector numbers and column names, SpotCheck threshold documents. Last commit January 2023 | None | Reference only: the query format, sample column names and thresholds, cited |
| [Support article: REST API automation with PowerShell](https://support.liquidware.com/hc/en-us/articles/21156817491981-Stratusphere-REST-API-Automation-using-PowerShell-Script) | The same batch-URL script pattern | Liquidware's terms | Facts only |
| [Blog: Stratusphere UX data in Power BI](https://www.liquidware.com/blog/extracting-liquidware-stratusphere-ux-data-with-microsoft-powerbi) (2019) | Power BI's web connector pointed at the API URL; scheduled refresh needs an on-premises data gateway | Liquidware's terms | Facts only |
| [Axonius adapter](https://docs.axonius.com/pl/docs/liquidware-stratusphere) | Reads device inventory from the API | Commercial | No |

## Not found

As of 2026-10-18, no public infrastructure-as-code deploys the Stratusphere appliances in Azure,
and no public PowerShell module or Python package wraps the Stratusphere API. The sample batch
script disables all TLS certificate checks; trust the Hub's certificate instead
([stratusphere/api.md](../stratusphere/api.md)).

The curator watches the liquidwarelabs organization and new GitHub repositories mentioning
Stratusphere ([sources.toml](../sources.toml)).
