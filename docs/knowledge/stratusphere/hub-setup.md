---
title: "First-time Hub setup"
summary: "What has to be set in the Hub console after deployment (license, API user, API allow list) and what might move to the API"
topic: stratusphere
status: unverified
last_reviewed: 2026-10-18
---

# First-time Hub setup

After the Hub VM is running, three things are set by hand in its web console. Whether the API can
do any of them is *unverified*: the Hub serves its own API reference (see [api.md](api.md)), and the
first lab run should check it for configuration calls.

1. **License.** Apply your Stratusphere license.
2. **API user.** Create a dedicated user for API access. The built-in admin account can't be used
   for the API *(unverified)*.
3. **API allow list.** Add the addresses that may call the API. Calls from anywhere else are
   refused.

Then, if they exist: point the Hub at the Database appliance, and register each Collector with the
Hub from the Collector's console ([appliances.md](appliances.md)).

Until the API covers these, this stays a checklist in the
[Stratusphere README](../../../stratusphere/README.md).
