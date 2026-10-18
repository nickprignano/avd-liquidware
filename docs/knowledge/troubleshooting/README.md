---
title: "Known errors"
summary: "Errors hit in this project: symptom, cause, fix and source"
topic: troubleshooting
status: partial
last_reviewed: 2026-10-18
---

# Known errors

Errors we've hit, what caused them and what fixed them. The table is generated from
[known-errors.yaml](known-errors.yaml); fixes marked *(unverified)* haven't been confirmed yet.

<!-- BEGIN GENERATED: known-errors (edit the YAML, then run scripts/kb/build.py) -->
| Symptom | Cause | Fix | Source |
|---|---|---|---|
| Connector ID Keys are installed but the Hub shows no data from them | The key calls the address in its mgrcert.pem, taken from the Hub's DNS name when the installer was downloaded; the address is wrong or unreachable on TCP 443 | Set the Hub's DNS name (Configuration > Edit Network Configuration), download the installer again and reinstall, or edit mgrcert.pem and restart the key's service; allow TCP 443 from the desktops to the Hub *(unverified)* | [link](https://support.liquidware.com/hc/en-us/articles/210640563-My-Stratusphere-does-not-receive-the-data-from-systems-where-Connector-ID-is-installed) |
<!-- END GENERATED: known-errors -->

## Adding an entry

Add an entry to [known-errors.yaml](known-errors.yaml) with the exact error text as the symptom,
the versions it was seen on in `applies_to`, and a `source` (a KB page or an https link). Or open a
**Known error** issue, and a maintainer turns it into a pull request.
