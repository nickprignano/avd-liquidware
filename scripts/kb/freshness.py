#!/usr/bin/env python3
"""List knowledge base pages that need a look: stale, unverified, or reported broken.

    python3 scripts/kb/freshness.py --max-age-days 90 --output freshness.md
    gh issue list --label kb-digest --state all --limit 30 --json createdAt,body > digests.json
    python3 scripts/kb/freshness.py --digests digests.json

Flags:
  - pages whose last_reviewed is older than --max-age-days
  - pages with status unverified or partial, with the count of claims marked *unverified* inline
  - pages with unresolved "broke" or "outdated" field reports
  - known errors whose fix is still unverified
  - experts not re-scored in --max-age-days, and nominations waiting to be scored
  - with --digests, each tracked expert's yield: digest items ticked as worth adding (experts.md)
  - with --family, siblings on a different family format version, unreadable, or not linked yet

Writes a Markdown checklist and, under GitHub Actions, items=<count> to GITHUB_OUTPUT.
"""

from __future__ import annotations

import argparse
import base64
import os
import json
import re
import sys
import tomllib
from datetime import date
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kblib  # noqa: E402
from kblib import rel  # noqa: E402

DIGEST_HEADING = re.compile(r"^### (.+?)(?: → .*)?$")
DIGEST_ITEM = re.compile(r"^- \[([ xX])\] ")
INLINE_UNVERIFIED = re.compile(r"\*(?:unverified|not verified)\b|not yet reviewed", re.I)


def digest_yield(digests: list[dict], since: date) -> dict[str, list[int]]:
    """Per source name: [items ticked, items listed] across digest issues created since a date."""
    counts: dict[str, list[int]] = {}
    for d in digests:
        if date.fromisoformat(d["createdAt"][:10]) < since:
            continue
        current = None
        for line in (d.get("body") or "").splitlines():
            if m := DIGEST_HEADING.match(line):
                current = m.group(1).strip()
            elif current and (m := DIGEST_ITEM.match(line)):
                c = counts.setdefault(current, [0, 0])
                c[1] += 1
                c[0] += m.group(1) != " "
    return counts


def expert_items(max_age_days: int, today: date, digests: list[dict] | None) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {"Experts to re-score": [], "Expert yield": []}
    experts = (kblib.load_yaml(kblib.EXPERTS) or {}).get("experts", [])
    for e in experts:
        if e["status"] == "nominated":
            ref = f" (#{e['issue']})" if e.get("issue") else ""
            out["Experts to re-score"].append(f"{e['name']}{ref}: nominated, not scored yet")
        elif (today - date.fromisoformat(e["reviewed"])).days > max_age_days:
            out["Experts to re-score"].append(f"{e['name']}: last scored {e['reviewed']}")
    if digests is None:
        return out
    since = date.fromordinal(today.toordinal() - max_age_days)
    counts = digest_yield(digests, since)
    sources = tomllib.loads(kblib.SOURCES.read_text(encoding="utf-8")).get("source", [])
    for e in experts:
        if e["status"] != "tracked":
            continue
        names = [s["name"] for s in sources if s.get("expert") == e["id"]]
        ticked = sum(counts.get(n, [0, 0])[0] for n in names)
        listed = sum(counts.get(n, [0, 0])[1] for n in names)
        if listed == 0:
            out["Expert yield"].append(f"{e['name']}: nothing in the digests since {since}; check the feed still works")
        elif ticked == 0:
            out["Expert yield"].append(f"{e['name']}: {listed} item(s) since {since}, none ticked; lower relevance or add keywords")
    return out


def read_sibling_family(project: dict) -> dict:
    """A sibling's own family.yaml, read through the GitHub contents API."""
    from sources import github
    data = github(f"/repos/{project['repo']}/contents/{kblib.kb_path(project)}/family.yaml")
    return yaml.safe_load(base64.b64decode(data["content"]).decode("utf-8")) or {}


def family_items(fetch=read_sibling_family) -> list[str]:
    """Siblings on a different format version, that can't be read, or that aren't linked yet."""
    data = kblib.family()
    ours = data.get("format_version")
    out = []
    for p in data.get("projects", []):
        if p.get("self") or p.get("role") == "observer":
            continue
        if not p.get("repo"):
            out.append(f"{p['name']}: repo not linked yet; add it to family.yaml, then its sources")
            continue
        try:
            theirs = fetch(p).get("format_version")
        except Exception as exc:
            out.append(f"{p['name']}: couldn't read its family.yaml ({type(exc).__name__}); "
                       "private repo, or not set up yet")
            continue
        if theirs != ours:
            out.append(f"{p['name']}: follows family format {theirs or 'none'}, this KB follows {ours}")
    return out


def collect(max_age_days: int, today: date, digests: list[dict] | None = None,
            fetch_family=None) -> dict[str, list[str]]:
    sections: dict[str, list[str]] = {"Reported broken or outdated": [], "Stale": [],
                                      "Unverified claims": [], "Unverified known-error fixes": []}
    reports = (kblib.load_yaml(kblib.FIELD_REPORTS) or {}).get("reports", [])
    open_reports: dict[str, list[dict]] = {}
    for r in reports:
        if r["outcome"] in ("broke", "outdated") and not r.get("resolved"):
            open_reports.setdefault(r["page"], []).append(r)

    for p in kblib.topic_pages():
        fm, body = kblib.split_front_matter(p.read_text(encoding="utf-8"))
        if not fm:
            continue
        page = rel(p)
        link = f"`docs/knowledge/{page}`"
        for r in open_reports.get(page, []):
            sections["Reported broken or outdated"].append(
                f"{link}: {r['outcome']} ({r['date']}, #{r['issue']}): {r['summary']}")
        age = (today - date.fromisoformat(fm["last_reviewed"])).days
        if age > max_age_days and fm["status"] != "plan":
            sections["Stale"].append(f"{link}: last reviewed {fm['last_reviewed']} ({age} days ago)")
        if fm["status"] in ("unverified", "partial"):
            n = len(INLINE_UNVERIFIED.findall(kblib.strip_code(body)))
            detail = f"{n} claim(s) marked unverified" if n else "no inline markers; re-check and update the status"
            sections["Unverified claims"].append(f"{link}: status {fm['status']}, {detail}")

    for e in (kblib.load_yaml(kblib.KNOWN_ERRORS) or {}).get("errors", []):
        if e["status"] == "unverified":
            sections["Unverified known-error fixes"].append(f"`{e['id']}`: {e['symptom'][:80]}")
    sections.update(expert_items(max_age_days, today, digests))
    if kblib.DIRECTIVES.exists():
        for d in (kblib.load_yaml(kblib.DIRECTIVES) or {}).get("directives", []) or []:
            if d.get("until") and date.fromisoformat(str(d["until"])) < today:
                sections.setdefault("Expired directives", []).append(
                    f"`{d['id']}`: past its until date ({d['until']}); remove it from directives.yaml")
    if fetch_family:
        sections["Family alignment"] = family_items(fetch_family)
    return sections


def render(sections: dict[str, list[str]], max_age_days: int) -> str:
    total = sum(len(v) for v in sections.values())
    lines = [
        f"Pages that need a look. Stale means not reviewed in {max_age_days} days.",
        "",
        "For each item: re-check the claim against a primary source or a real run, update the page,",
        "set `last_reviewed` (and `status` if it changed), and mark any field report `resolved: true`.",
        "For experts, re-score them in `docs/knowledge/experts.yaml` using the method in `experts.md`.",
        "",
    ]
    for title, items in sections.items():
        if items:
            lines += [f"## {title}", ""] + [f"- [ ] {i}" for i in items] + [""]
    if not total:
        lines.append("Nothing to review.")
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--max-age-days", type=int, default=90)
    ap.add_argument("--today", help="override today's date (YYYY-MM-DD), for testing")
    ap.add_argument("--output", help="write the report here instead of stdout")
    ap.add_argument("--family", action="store_true",
                    help="read each sibling's family.yaml from GitHub and compare format versions")
    ap.add_argument("--digests", help="JSON from gh issue list --label kb-digest (createdAt, body), for expert yield")
    args = ap.parse_args()

    today = date.fromisoformat(args.today) if args.today else date.today()
    digests = json.loads(Path(args.digests).read_text(encoding="utf-8")) if args.digests else None
    sections = collect(args.max_age_days, today, digests,
                       fetch_family=read_sibling_family if args.family else None)
    report = render(sections, args.max_age_days)
    if args.output:
        Path(args.output).write_text(report, encoding="utf-8")
    else:
        print(report)
    if gh_out := os.environ.get("GITHUB_OUTPUT"):
        with open(gh_out, "a", encoding="utf-8") as f:
            f.write(f"items={sum(len(v) for v in sections.values())}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
