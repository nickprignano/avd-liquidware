---
title: "Stratusphere API"
summary: "The Hub's read-only data API: the request shape, authentication, output formats and the built-in reference"
topic: stratusphere
status: partial
last_reviewed: 2026-10-18
sources:
  - https://docs.liquidware.com/stratusphere/en-us/common/stratusphere-getting-started-api-guide/using-the-api.htm
  - https://docs.liquidware.com/stratusphere/en-us/common/stratusphere-getting-started-api-guide/accessing-api-and-documentation.htm
---

# Stratusphere API

The Hub serves a data API for what Stratusphere collects. It reads data; whether it can change Hub
settings is *unverified*. From Liquidware's
[API guide](https://docs.liquidware.com/stratusphere/en-us/common/stratusphere-getting-started-api-guide/using-the-api.htm):

- Requests go to `https://<hub>/lwl/api?json={...}`, as GET or POST.
- `inspector` is required and picks the data set; `basis` is the group-by. Without a time window
  the default is yesterday.
- Output can be JSON, CSV or Excel.
- Access is limited by an IP allow list, optionally with Basic authentication as
  `username@domain` ([access guide](https://docs.liquidware.com/stratusphere/en-us/common/stratusphere-getting-started-api-guide/accessing-api-and-documentation.htm)).
- Each Hub serves its full option reference at `/lwl/api`. The self-documenting page at
  `/cgi-bin/mentok/run.cgi` is *unverified*.

## Gotchas

- The Hub's certificate is self-signed by default. Trust that certificate in the client instead of
  turning TLS checks off; Liquidware's own sample batch script disables them
  ([community-projects.md](../liquidware/community-projects.md)).
- Inspector exports to Excel cap at 99,999 rows per sheet *(unverified)*.
- Assessment data holds user and machine names. It stays in git-ignored output folders and never
  goes into this repo, issues or the KB.

This page holds facts about the API itself: what it accepts, returns and refuses.
