#!/usr/bin/env python3
"""Collect what's new in the sources the knowledge base watches.

Reads docs/knowledge/sources.toml, fetches items newer than --since-days, drops anything the KB
already links to, and writes a Markdown digest. No LLM involved; a person (or a scheduled Claude
routine) decides what goes into the KB.

    python3 scripts/kb/curate.py --since-days 8 --output digest.md
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import tomllib
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sources import FETCHERS  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
KB_DIR = ROOT / "docs" / "knowledge"


def known_urls(kb_dir: Path) -> set[str]:
    urls = set()
    for md in kb_dir.rglob("*.md"):
        urls.update(u.rstrip(").,") for u in re.findall(r"https?://[^\s)>\]]+", md.read_text()))
    return urls


def matches(keywords: list[str], text: str) -> bool:
    if not keywords:
        return True
    lowered = text.lower()
    return any(k.lower() in lowered for k in keywords)


def collect(sources: list[dict], since: datetime, known: set[str]):
    results, errors = [], []
    for src in sources:
        fetch = FETCHERS.get(src["kind"])
        if fetch is None:
            errors.append((src["name"], f"unknown kind '{src['kind']}'"))
            continue
        try:
            items = fetch(src, since)
        except Exception as exc:  # one broken source shouldn't sink the digest
            errors.append((src["name"], f"{type(exc).__name__}: {exc}"))
            continue
        keywords = src.get("keywords", [])
        items = [i for i in items
                 if i.url not in known and matches(keywords, f"{i.title}\n{i.text}")]
        if items:
            results.append((src, sorted(items, key=lambda i: i.date, reverse=True)))
    return results, errors


def render(results, errors, since: datetime) -> str:
    total = sum(len(items) for _, items in results)
    lines = [
        f"New since {since.date().isoformat()}: **{total}** item(s) from "
        f"{len(results)} source(s). Tick what's worth adding to the KB, and note which page.",
        "",
    ]
    for src, items in results:
        page = src.get("kb_page")
        lines.append(f"### {src['name']}" + (f" → `docs/knowledge/{page}`" if page else ""))
        for i in items:
            note = f" ({i.note})" if i.note else ""
            lines.append(f"- [ ] [{i.title}]({i.url}) · {i.date.date().isoformat()}{note}")
        lines.append("")
    if errors:
        lines.append("<details><summary>Sources that failed this run</summary>\n")
        lines += [f"- {name}: {err}" for name, err in errors]
        lines.append("\n</details>")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--sources", type=Path, default=KB_DIR / "sources.toml")
    parser.add_argument("--since-days", type=int, default=8)
    parser.add_argument("--output", type=Path, help="write the digest here (default: stdout)")
    args = parser.parse_args()

    sources = tomllib.loads(args.sources.read_text())["source"]
    since = datetime.now(timezone.utc) - timedelta(days=args.since_days)
    results, errors = collect(sources, since, known_urls(KB_DIR))
    digest = render(results, errors, since)

    if args.output:
        args.output.write_text(digest)
    else:
        sys.stdout.write(digest)

    if gh_out := os.environ.get("GITHUB_OUTPUT"):
        with open(gh_out, "a") as fh:
            fh.write(f"items={sum(len(i) for _, i in results)}\n")
            fh.write(f"failed={len(errors)}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
