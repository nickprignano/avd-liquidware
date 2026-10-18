---
title: "Experts we follow"
summary: "How we choose which people on this KB's topics the KB follows: the method, the scores and the list"
topic: curation
status: verified
last_reviewed: 2026-10-18
---

# Experts we follow

The weekly digest ([curation.md](curation.md#weekly-digest-kb-curator)) watches a set of people
who write about this KB's topics. This page explains how that
list is chosen, so anyone can check it, re-run it or challenge it. The data is in
[experts.yaml](experts.yaml), and the tables below are generated from it. The method is the same in
every KB of the family; each KB scores people against its own topic.

<!-- BEGIN GENERATED: experts-balance (from experts.yaml; run scripts/kb/build.py) -->
Last scored 2026-10-18: 1 tracked (1 vendor-staff), 1 on the watch list, 0 declined, 0 nominated and waiting to be scored.
<!-- END GENERATED: experts-balance -->

## This KB's study

First run 2026-10-18. Few people outside Liquidware publish on Stratusphere, so the list is short:
searches of the web, Liquidware's blog and support center, GitHub and the sibling KBs' expert lists
turned up no independent author with recent, original Stratusphere content. The vendor's own feed is
tracked as the control source, and its GitHub organization is on the watch list. Nominations are
welcome through the **Suggest an expert to follow** issue form.

## The method

It works like a small systematic review: the rules are fixed before anyone is scored, they're
applied the same way to everyone, and every score points at evidence.

### 1. Find candidates in several places

One list brings its author's blind spots with it, so candidates come from several channels, and
each entry records which ones found it (`found_via`):

- The vendors' own channels: docs, sample and course authors, and people they feature
- Speakers at conferences and meetups on the topic
- GitHub: maintainers of tools people use, and the KB's prior-art searches
- Blogs and newsletters that post on these topics more than once
- Snowballing: who the people already on the list link to, cite or present with
- The sibling KBs' expert lists ([family.yaml](family.yaml)); use the same `id` for the same person
- Nominations through the **Suggest an expert to follow** issue form

### 2. Apply the gates

A candidate must pass all four gates to be tracked. Organisations go through the same gates and
scores as people. Failing identity or originality declines them; failing only recency or feed puts
them on the watch list if their score is high enough.

| Gate | Passes when |
|---|---|
| Original | They publish their own technical content, not just reshares or marketing |
| Recent | They've posted on the topic in the last 12 months |
| Feed | A free, machine-readable feed exists: blog RSS or Atom, a YouTube channel or a GitHub account. X isn't one, because its API is paid |
| Identity | We know who's behind every account we'd watch: one of their own profiles links the others, or we watch only one account |

### 3. Score five things from 0 to 3

| Score | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| Relevance | Rarely on topic | Occasionally | A regular topic | Their main topic |
| Depth | Announcements only | Overviews | How-tos with steps | Code, evals or gotchas others can reuse |
| Recency | Nothing on topic in 12 months | Within 12 months | Within 6 months | Within 3 months |
| Track record | Unknown | Some engagement | Cited or reused by others | Widely cited, or maintainer of a tool people use |
| Feedability | No free feed | A feed, mostly off topic | A feed that keyword filters can fix | A clean, on-topic feed |

The total is out of 15.

- **Tracked:** all gates pass and the total is 10 or more. They get a `[[source]]` in
  [sources.toml](sources.toml) with `expert = "<id>"`.
- **Watch:** identity and originality pass and the total is 6 or more. Re-checked each review, not
  in the digest.
- **Declined:** everything else, with the reason, so the same person isn't re-researched for
  nothing.

`scripts/kb/validate.py` enforces these rules: an entry's status must match its gates and scores,
every tracked expert must have a source, and every source with an `expert` must be tracked.

**Affiliation is recorded but not scored.** Vendor staff often know the product best, so they
aren't marked down. The summary above shows the mix, so a list that's all one company's voices is
visible.

### 4. Measure and review

- **Yield:** the monthly freshness check reads recent digest issues and counts, per tracked
  expert, how many of their items were ticked as worth adding. A source that lists nothing, or
  only items nobody ticks, is flagged to re-score or narrow with `keywords`.
- **Cadence:** everyone is re-scored every 90 days. The freshness check lists anyone not re-scored
  in 90 days and any nomination waiting to be scored.
- **Nominations:** the issue form adds the person as `nominated`. When a maintainer labels it
  `kb-accepted`, the feedback workflow opens a PR, and the maintainer scores them in that PR.

### What's recorded about people

Only what they publish professionally: the name they use, their public links, and their
affiliation if they state it. No emails, locations or other personal details. Anyone listed can
ask to be removed by opening an issue.

## Tracked

<!-- BEGIN GENERATED: experts-tracked (from experts.yaml; run scripts/kb/build.py) -->
| Name | Affiliation | Links | Score (rel/depth/recency/record/feed) | Latest AI post | Notes |
|---|---|---|---|---|---|
| Liquidware news and blog | vendor-staff | [blog](https://www.liquidware.com/newsroom) | 11 (2/1/3/2/3) | [2026-09-25](https://www.liquidware.com/event/7-practical-strategies-reduce-your-avd-spend) | The vendor's own feed: product releases, webinars and events, mostly marketing. Kept as the control source for releases, filtered by keywords in sources.toml. |
<!-- END GENERATED: experts-tracked -->

## Watch list

<!-- BEGIN GENERATED: experts-watch (from experts.yaml; run scripts/kb/build.py) -->
| Name | Affiliation | Links | Score (rel/depth/recency/record/feed) | Latest AI post | Notes |
|---|---|---|---|---|---|
| Liquidware Labs on GitHub | vendor-staff | [GitHub](https://github.com/liquidwarelabs) | 9 (3/2/0/2/2) | none found | Fails: recent. SE PowerTools with sample API queries and SpotCheck thresholds; last commit January 2023 and no license, so reference only. Its commits and new repos are watched as plain sources. |
<!-- END GENERATED: experts-watch -->

## Declined

<!-- BEGIN GENERATED: experts-declined (from experts.yaml; run scripts/kb/build.py) -->
None.
<!-- END GENERATED: experts-declined -->

## Nominated, not scored yet

<!-- BEGIN GENERATED: experts-nominated (from experts.yaml; run scripts/kb/build.py) -->
None waiting.
<!-- END GENERATED: experts-nominated -->
