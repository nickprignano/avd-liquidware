---
title: "Keeping the knowledge base current"
summary: "How the KB stays current: the weekly digest, the prior-art check, the feedback loop, the freshness check and family alignment"
topic: curation
status: verified
last_reviewed: 2026-10-18
---

# Keeping the knowledge base current

Four tools keep the KB current without spending time (or LLM tokens) rediscovering things. Two
bring new information in (the weekly digest and the prior-art check), and two check that what's
already here still holds (the feedback loop and the monthly freshness check). A fifth part keeps
this KB aligned with its siblings.

## Weekly digest (`kb-curator`)

[`.github/workflows/kb-curator.yml`](../../.github/workflows/kb-curator.yml) runs every Monday.
It reads [sources.toml](sources.toml), collects anything new from the last 8 days and opens an
issue labelled **kb-digest** with a checklist grouped by source. Each source names the KB page its
findings belong on. Items whose URL is already linked from the KB are left out. If nothing is new,
no issue is opened.

Watched today:

- Liquidware's support center (Zendesk) and news feed, filtered to what this KB covers
- Liquidware Labs on GitHub, and new GitHub repositories mentioning Stratusphere
- The 2ndbrain-public template, for changes to the shared machinery
- The sibling KBs' decisions and other changes (see [Staying aligned](#staying-aligned-with-the-family))

Some sources have no feed, so they're checked by hand when a page depends on them: Liquidware's
product documentation at docs.liquidware.com, and the `stratusphere` offer in Azure Marketplace
([liquidware/products.md](liquidware/products.md)). People are chosen with the method in
[experts.md](experts.md), and a blog feed is added only once a curator run shows it works.

Working a digest: for each ticked item, add what matters to the page named next to the source
(facts, versions, fixes; not a link dump), then close the issue.

To watch something else, add a `[[source]]` table to [sources.toml](sources.toml). Supported
kinds: `github_releases`, `github_commits` (optionally limited to one `path`), `github_issues`,
`github_org_repos`, `github_user_repos`, `github_search`, `feed`
(RSS/Atom, with optional `keywords`) and `zendesk`. Run it locally with:

```bash
GITHUB_TOKEN=$(gh auth token) python3 scripts/kb/curate.py --since-days 30
```

A source that fails (rate limit, site down) is listed at the bottom of the digest and doesn't
stop the others.

## Prior-art check (`kb-prior-art`)

Before building something new, check whether it's already solved:

```bash
GITHUB_TOKEN=$(gh auth token) python3 scripts/kb/prior_art.py "stratusphere hub api"
```

or run **Actions > kb-prior-art** with the topic. It searches, in order: this KB, each sibling KB
in [family.yaml](family.yaml), GitHub repositories, Python and TypeScript code, and issues and pull
requests. If something useful turns up, record it on the relevant topic page, so the next person
doesn't search again.

The digest and prior-art scripts use only the Python standard library (3.11+).

## Feedback loop (`kb-feedback`)

Real results flow back into the KB through three issue forms:

- **Knowledge base feedback:** what worked, broke, went out of date or is missing, for one page
  (label `kb-feedback`).
- **Known error:** an error, its cause and fix, for the [troubleshooting catalog](troubleshooting/README.md)
  (label `kb-known-error`).
- **Suggest an expert to follow:** a nomination for the [experts study](experts.md) (label `kb-source`).

Each form has a required public-safe tick box. A maintainer reviews the issue and, if it's useful
and public-safe, labels it **kb-accepted**.
[`.github/workflows/kb-feedback.yml`](../../.github/workflows/kb-feedback.yml) then appends it to
[field-reports.yaml](field-reports.yaml), [known-errors.yaml](troubleshooting/known-errors.yaml) or
[experts.yaml](experts.yaml), regenerates and validates the KB, and opens a pull request that closes
the issue. If the form is incomplete or fails validation, the workflow comments on the issue instead.

The label is the safety gate: issue text from anyone is only parsed as data, never executed, the PR
still goes through review, and gitleaks and the KB checks run on it. Two one-time settings matter:

- Run **Actions > kb-freshness** once so the `kb-*` labels exist (issue forms only apply labels
  that already exist).
- Turn on **Settings > Actions > General > Allow GitHub Actions to create and approve pull
  requests**. Without it, the workflow pushes the branch and asks you to open the PR.

Pull requests opened by the workflow's own token don't start other workflows. The job runs the KB
checks itself; close and reopen the PR to run the full CI before merging.

## Freshness check (`kb-freshness`)

[`.github/workflows/kb-freshness.yml`](../../.github/workflows/kb-freshness.yml) runs on the 1st
of each month and keeps one open issue labelled **kb-freshness** listing:

- pages reported broken or outdated in field reports that aren't marked `resolved` yet
- pages whose `last_reviewed` is more than 90 days old (pages with status `plan` are skipped)
- pages with status `unverified` or `partial`, with the number of claims still marked *unverified*
- known errors whose fix is still unverified
- experts due for re-scoring, with each tracked expert's digest yield
- sibling KBs on a different family format version, or whose `family.yaml` can't be read

Work it by re-checking each item against a primary source or a real run, then updating the page's
text, `last_reviewed` and `status`. Run it locally with `python3 scripts/kb/freshness.py --family`.

## Staying aligned with the family

[family.yaml](family.yaml) lists every KB in the family, this one included (`self: true`): its
repo, KB path, role, focus, what it's the source of truth for (`owns`) and the family format version.
A sibling without a `repo` isn't linked yet. `build.py` turns the file into the
"Related knowledge bases" table in the [KB README](README.md#related-knowledge-bases) and a section
in `llms.txt`. The schema and the family code in `scripts/kb/` are the same in every KB.

- **Watch each other.** Each set-up sibling gets two `github_commits` sources in
  [sources.toml](sources.toml): one with `path` set to its decisions folder, and one with `path` set
  to its KB folder. `validate.py` fails if either is missing for a sibling with a `repo`. A private sibling can't be read with
  the built-in token; its sources stay in and start working once the repo is public.
- **Link instead of copying.** When a fact belongs to a sibling's topic, link to their page. When we
  learn something they need, open an issue or PR on their repo with the evidence. If two KBs
  disagree, the one closer to the topic is the source of truth, and the other links to it.
- **Share the format, not the content.** The schemas, scripts, checks, workflows and guardrails stay
  the same in every KB. To change them, write a proposed decision titled "Family format: ..." in
  one KB, open the same change in the others, and bump `format_version` in every `family.yaml` once
  all of them have merged. The freshness check flags a sibling whose version differs.
- **Cross-project decisions.** A decision that affects more than one project is recorded in each
  affected KB, and each copy says "Also recorded in ..." with links.

## Checks on every change (`kb-validate`)

[`.github/workflows/kb-validate.yml`](../../.github/workflows/kb-validate.yml) runs on pull
requests that touch the KB. It runs `validate.py` (front matter and YAML against the
[schemas](schema/page.schema.json), MADR sections, duplicate ids, KB paths the data references,
links and anchors, email and public-IP patterns, and the family checks), checks the generated
tables and `llms.txt` are up to date (`build.py --check`), and runs the KB scripts' unit tests.
Secrets are caught by gitleaks in [`secrets.yml`](../../.github/workflows/secrets.yml), on every PR.
