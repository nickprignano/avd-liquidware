#!/usr/bin/env python3
"""Check for prior art before starting new work.

Searches this repo's knowledge base, then the sibling KBs in family.yaml, then GitHub repositories,
code and issues for a topic, and prints a Markdown report. Run it before building something so you can reuse what
others have already figured out, and record anything useful in docs/knowledge/.

    GITHUB_TOKEN=$(gh auth token) python3 scripts/kb/prior_art.py "prompt caching"

Code search (and so the sibling search) needs a token; repository and issue search work without one (at a lower rate limit).
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kblib  # noqa: E402
from sources import github  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
KB_DIR = ROOT / "docs" / "knowledge"
# Code most relevant to this KB: Python and TypeScript/JavaScript that calls models.
CODE_EXTENSIONS = ("py", "ts", "js")


def search_kb(terms: list[str]) -> list[str]:
    hits = []
    for md in sorted(KB_DIR.rglob("*.md")):
        for n, line in enumerate(md.read_text(encoding="utf-8").splitlines(), 1):
            if all(t.lower() in line.lower() for t in terms):
                hits.append(f"- `{md.relative_to(ROOT)}:{n}` {line.strip()[:160]}")
    return hits


def section(title: str, fn) -> list[str]:
    try:
        rows = fn()
    except Exception as exc:
        return [f"### {title}", f"_Search failed: {type(exc).__name__}: {exc}_", ""]
    return [f"### {title}", *(rows or ["_Nothing found._"]), ""]


def repos(query: str, limit: int) -> list[str]:
    data = github("/search/repositories", {"q": query, "sort": "stars", "per_page": limit})
    return [
        f"- [{r['full_name']}]({r['html_url']}) · {r['stargazers_count']}★ · "
        f"updated {r['pushed_at'][:10]}" + (f" · {r['description']}" if r.get("description") else "")
        for r in data.get("items", [])
    ]


def code(query: str, limit: int) -> list[str]:
    if not (os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")):
        return ["_Skipped: GitHub code search needs GITHUB_TOKEN._"]
    rows = []
    for ext in CODE_EXTENSIONS:
        data = github("/search/code", {"q": f"{query} extension:{ext}", "per_page": limit})
        rows += [
            f"- [{i['repository']['full_name']}/{i['path']}]({i['html_url']})"
            for i in data.get("items", [])
        ]
    return rows


def sibling(project: dict, query: str, limit: int) -> list[str]:
    if not (os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")):
        return ["_Skipped: searching sibling KBs needs GITHUB_TOKEN._"]
    q = f"{query} repo:{project['repo']} path:{kblib.kb_path(project)}"
    return [f"- [{i['path']}]({i['html_url']})" for i in github("/search/code", {"q": q, "per_page": limit}).get("items", [])]


def issues(query: str, limit: int) -> list[str]:
    data = github("/search/issues", {"q": query, "sort": "updated", "per_page": limit})
    return [
        f"- [{i['title']}]({i['html_url']}) · {i['state']} · {i['updated_at'][:10]}"
        for i in data.get("items", [])
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("query", help='what you are about to build, e.g. "prompt caching"')
    parser.add_argument("--limit", type=int, default=10)
    args = parser.parse_args()

    out = [f"## Prior art: {args.query}", ""]
    out += ["### Already in our knowledge base", *(search_kb(args.query.split()) or ["_Nothing yet._"]), ""]
    for p in kblib.siblings():
        out += section(f"Sibling KB: {p['name']}", lambda p=p: sibling(p, args.query, args.limit))
    out += section("GitHub repositories", lambda: repos(args.query, args.limit))
    out += section("Code", lambda: code(args.query, args.limit))
    out += section("Issues and pull requests", lambda: issues(args.query, args.limit))
    report = "\n".join(out) + "\n"

    sys.stdout.write(report)
    if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
