# 2ndbrain: the specification

A second brain is a knowledge base that a project keeps for itself: what it learned, what it
decided and why, what broke and how it was fixed. It's written so that people, tools and AI agents
can all read it, and kept current by small, token-free automation. This page specifies the system:
the layers, the format, the loops that keep a KB current, how sibling KBs stay aligned, and the
optional private layer above them. Agents working in a 2ndbrain repo follow the
[2ndbrain-kb skill](../../.claude/skills/2ndbrain-kb/SKILL.md), which is this spec turned into steps.

Status: version 1 of the family format, in use by four project KBs. Format ownership and
directives (decisions 0007 and 0008) are accepted and built in the hub; siblings adopt them by PR.
The upstream rules in section 5 apply now; the checks proposed there wait for format version 2.

## 1. Layers

| Layer | Visibility | What it holds | Example |
|---|---|---|---|
| **Project KB** | Public | One project's facts, gotchas with versions, decisions and known errors | A deployment kit's KB |
| **Hub KB** | Public | Knowledge every project uses, plus the family format itself | A KB on the AI tooling all the projects share |
| **Private layer** | Private | One person's judgment above all the projects: patterns, lessons, goals | A personal notes vault |

- A project KB lives inside its project repo, at `docs/knowledge/`, so the knowledge changes in the
  same PR as the code it describes.
- Signal flows **up**: project KBs into the hub, through the hub's weekly digest, and from the hub
  into the private layer.
- Instructions flow **down** only through the hub, as owner-approved directives (section 7).
- The private layer reads the hub, which is public, and needs no credential to do it. Nothing
  inside it ever reaches a public repo.

## 2. The format (version 1)

Open, common formats only:

- **Pages:** Markdown with YAML front matter: `title` (the same as the H1), `summary`, `topic`,
  `status` (`verified`, `partial`, `unverified` or `plan`) and `last_reviewed`. Each topic has one
  page, and new knowledge goes on the page it belongs to, never in a new file. Claims not yet
  confirmed are marked *unverified*.
- **Decisions:** [MADR 4](https://adr.github.io/madr/) records in `decisions/NNNN-title.md`, with
  `status`, `date` and `decision-makers` in front matter. A decision stays `proposed` until the
  maintainer says yes, and a reversal gets a new record that supersedes the old one.
- **Structured data:** YAML files, each with a JSON Schema in `schema/`. They cover known errors,
  field reports, the experts study, the family and directives. The Markdown tables
  are generated from them.
- **Generated blocks:** sit between `BEGIN GENERATED` and `END GENERATED` comments. You edit the
  source, never the output. A folder of many small pages, such as a prompt library, lists them in
  its README with a `folder-index` block; the main index lists only the folder.
- **[`llms.txt`](https://llmstxt.org):** generated at the repo root, so LLMs and agents find
  everything.
- **Identity:** `docs/knowledge/kb.toml` holds the only settings that differ between KBs: name,
  title, tagline, user agent, topic order, and the data files to list. Every other script and
  schema is the same in every KB.
- **Tooling:** Python 3.11+ with PyYAML and jsonschema, run on GitHub Actions with the built-in
  token. It needs no LLM calls and no API keys.

## 3. Keeping a KB current

Two loops bring information in and two check that it still holds. All four are issues or PRs that
a person reviews.

| Loop | When | What it does |
|---|---|---|
| Weekly digest (`kb-curator`) | Mondays | Reads `sources.toml` (releases, commits, issues, feeds) and opens one checklist issue of new items, leaving out anything the KB already links |
| Prior-art check (`kb-prior-art`) | Before building anything | Searches this KB, the sibling KBs, then GitHub, and records what it finds on the topic page |
| Feedback (`kb-feedback`) | When someone reports a result | Issue forms (feedback, known error, expert nomination). A maintainer's `kb-accepted` label turns one into a PR that appends to the YAML |
| Freshness (`kb-freshness`) | The 1st of each month | One issue listing stale pages, open unverified claims, unresolved field reports, experts due for re-scoring, and sibling drift |

On every PR, `kb-validate` runs `build.py --check`, `validate.py` (schemas, MADR sections, links and
anchors, leak patterns, family checks) and the unit tests, and gitleaks scans for secrets.

**Capture is enforced (decision 0011, piloted first).** A Claude Code Stop hook asks for the lesson
when a session changed code but not `docs/knowledge/`, and the `kb-capture` check fails a PR that
does the same unless it carries the `no-kb` label and a reason. A repo without its own KB links the
lesson in the KB it feeds instead. Threads also run the capture closeout before they're resolved.
Both checks use only git; `capture_hook` in `kb.toml` sets the hook to block, warn or off.

Experts
are chosen by a fixed method: four gates (original, recent, feed, identity) and five scores from 0
to 3. A total of 10 or more is tracked, 6 or more goes on the watch list.

## 4. The family

`docs/knowledge/family.yaml` lists every KB in the family, this one included (`self: true`), with
its repo, KB path, role (`reference` for the KB that owns the format and is the hub, `member`, or `observer` for a
private layer with no repo; `hub` is the older name), focus, what
it's the source of truth for, and the format version it follows.

- **Watch each other.** Each sibling with a repo gets two `github_commits` sources in this KB: one
  on its decisions folder and one on its KB folder. `validate.py` fails if either is missing.
- **Link, don't copy.** A fact that belongs to a sibling's topic is linked, never copied. If two
  KBs disagree, the one closer to the topic is the source of truth.
- **Share the format, not the content.** Format changes start as a "Family format: ..." decision in
  the KB that owns the format, which is the hub (the `reference` row). Each sibling adopts the change by
  PR, and `format_version` goes up once all of them have merged it. The freshness check flags a
  sibling on another version.
- **Cross-project decisions** are recorded in each affected KB, and each record says where else
  it's recorded.

## 5. Upstream sources

A KB is not a second copy of anyone else's documentation. Vendor docs sites, product repos and SDK
repos are **upstream**: the sources of truth for what a product is documented to do. A paraphrase
goes stale the day the original changes, and nothing says it did. So a KB links out, checks
against upstream, and gives back what it learns.

### The rules (format version 1, in force now)

- **Link, don't restate.** A page says only what upstream doesn't: a gap, a contradiction found in
  a real run, or how documented pieces combine. For everything else it links the upstream page. A
  sibling's topic still gets a link to the sibling (section 4); an upstream topic gets a link to
  upstream.
- **Who wins.** Upstream is the source of truth for what a product is documented to do. A real run
  is the source of truth for what it did. When they disagree, the page keeps the finding, links
  both, and the disagreement becomes an upstream ask.
- **Verified means checked against the source.** A page is `verified` when its claims were checked
  against a primary source or a real run, and every claim about documented behavior links the
  source it was checked against.
- **Giving back is a person's act.** An ask starts as a `candidate` in the KB's `upstream.yaml`,
  its text is drafted and reviewed in a PR, and a person files it upstream under their own account
  and records `status: raised` and the link. An agent opens issues and PRs only on the family's own
  repos (`family.yaml`) and its project's repos; anything else is upstream.
- **What a draft may hold.** Generic reproduction steps and public evidence only: nothing from a
  real estate, tenant or account, no IDs or secrets (section 6), and nothing from the private layer.
  It follows the upstream's own contributing rules, license and CLA, uses their template, and says
  which upstream page or version it was checked against.
- **The default upstream set** is the docs sites the KB names for its topics plus the repos it
  watches in `sources.toml`. The weekly digest reports upstream changes; when one touches a page,
  the page is re-checked and `last_reviewed` updated.

### Proposed for format version 2

Not built yet. It ships once every KB in the family accepts it, in the same version bump as the
other queued format changes, so siblings change version once.

| Change | What it does |
|---|---|
| `upstream:` in page front matter | An optional list of `https://` URLs the page builds on. `validate.py` checks the shape. An empty list says no upstream applies |
| `upstream_docs` in `kb.toml` | The KB's primary docs sites, its default upstream set. The first one is the default target of an ask |
| Upstream freshness | `freshness.py --upstream`, passed only by the monthly job, warns on `verified` pages with no `upstream` field and on pages whose upstream changed after `last_reviewed`: a GitHub file's last commit, a docs page's own date metadata, or its `Last-Modified` header. A URL with no readable date is listed as "can't tell". Warnings never fail the run |
| One `upstream/` folder | `upstream.yaml` and its page move from a vendor folder to `upstream/` in every KB, with `upstream/drafts/` beside them, so the shared code points at one path |
| Any upstream | Entries gain an optional `target` (a repo, docs set or product team), a `drafted` status between `candidate` and `raised`, and a `draft` path. `drafted` needs the draft file; `raised` and `merged` need `link` |

## 6. Guardrails

The same in every KB, worded for each one's topic:

1. **Nothing public identifies a real account or project.** No keys, IDs, domains, emails, real
   IPs, or employer, customer or private-project names. CI checks this.
2. **Secrets never pass through chat, the repo or the KB.** The user runs the step that handles a
   secret.
3. **Every change goes through a PR.** Nothing touches a real account without its owner's yes.
4. **Unlicensed code is reference only.** Use its facts, cite it, never copy it.
5. **Free and open tooling first.** A paid service needs a decision record.
6. **Every step works from a browser.**
7. **Every decision and lesson goes into the KB.**

## 7. Directives and the pause switch

One owner-only `directives.yaml` in the hub tells the whole family something at once.

- **Entries:** each has an `id`, the `directive` (at most 280 characters), a `scope` (`all` or
  family ids), an optional `pause` list of `kb-*` workflows, an optional `until` date and an
  `opened` date. There's no field for reasons: a directive carries only the instruction.
- **Only the owner's merge counts,** enforced by CODEOWNERS and a `kb-validate` step that fails a PR
  changing the file unless the repo owner opened it. `validate.py` allows at most five active.
- **Fan-out:** every KB's automated `kb-*` runs read the file from the public hub first and skip
  when a pause covers them (`scripts/kb/directives.py gate`). A daily `kb-directives` workflow
  opens a local pointer issue for each directive in scope and closes it when the directive goes. No repo holds a credential for another.
- **Instant stop:** a `KB_PAUSED` repository variable stops that repo's automation at once.
  `kb-validate` and the secret scan always run.

## 8. The private layer

An optional private repo above the family, for one person's judgment. It's described generically
here, and the [2ndbrain-private template](https://github.com/nickprignano/2ndbrain-private) is a
starting point.

- **Note types, and when each is written:**
  - **Lessons:** at the end of a piece of work.
  - **Root-cause analyses:** only after troubleshooting.
  - **Procedures:** for steps the person is in the loop for.
  - **Decisions and goals:** offered when the person needs to exercise judgment.
  - **Disagreements:** only when the person asks for one.
  - **Patterns:** when the same lesson shows up in two or more KBs.
- **Review clocks:** each note carries one, and a stale check runs before every commit.
- **Roll-up:** a weekly private issue lists what the hub's digest, decisions and field reports
  turned up. That's the input for pattern notes.
- **The way down:** the person approves a directive in the private layer. It's checked for
  anything that points back inside, queued in an outbox, opened as a PR in the hub, and acts only
  once the hub's owner merges it.
- **Privacy rules:**
  - Contents never leave the private repo.
  - Directives carry no reasoning.
  - No employer or customer material goes into it at all.
  - Public text may say the layer exists. It never names its repo, its notes or their paths.

## 9. Templates

- **[2ndbrain-public](https://github.com/nickprignano/2ndbrain-public)** is the machinery and an
  empty KB skeleton. It's generated from the hub by `scripts/kb/export_template.py`, following
  `template/manifest.toml`, and the template repo pulls that export weekly.
- **[2ndbrain-private](https://github.com/nickprignano/2ndbrain-private)** is the private layer's
  starting point. It's written generically and never generated from a real vault.
- **Starting a KB the same way every time.** A new repo uses the template. An existing repo, or a
  KB joining a family, installs the machinery from the format owner's own export, makes `kb.toml`,
  topics and sources its own, copies the owner's `family.yaml` with its own row marked `self`, and
  asks the owner by PR to fill in its row. The steps are in the
  [skill](../../.claude/skills/2ndbrain-kb/SKILL.md#setting-up-a-new-kb).

## Credits

The project second brain started as a work prototype for a complex enterprise migration
engagement: an agent grounded in a human-curated document site, with a chat front end for everyone
on the project. Brian Madden (Citrix) put the name "second brain" on it in one of his videos, and
Meta's article on an organizational second brain showed where the idea could go the same day. The
format's first implementation was nerdio-hcl, under Apache-2.0.
