#!/usr/bin/env python3
"""Regenerate the knowledge base's generated parts from front matter and YAML data.

Generated:
  - the index table in docs/knowledge/README.md (from page front matter)
  - the list in docs/knowledge/decisions/README.md (from decision records)
  - the tables in troubleshooting/README.md, anthropic/upstream-contributions.md and experts.md (from YAML)
  - the "Related knowledge bases" table in docs/knowledge/README.md (from family.yaml)
  - llms.txt at the repo root (from all of the above)

    python3 scripts/kb/build.py           # rewrite files
    python3 scripts/kb/build.py --check   # exit 1 if anything is out of date (CI)
"""

from __future__ import annotations

import argparse
import re
import sys
import textwrap
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kblib  # noqa: E402
from kblib import KB_DIR, rel  # noqa: E402

BLOCK = re.compile(
    r"(<!-- BEGIN GENERATED: (?P<name>[\w-]+)[^>]*-->\n)(?P<body>.*?)(<!-- END GENERATED: (?P=name) -->)",
    re.S,
)
TOPIC_ORDER = kblib.kb_config()["topic_order"]


def cell(text: str) -> str:
    return " ".join(str(text).split()).replace("|", "\\|")


def table(headers: list[str], rows: list[list[str]]) -> str:
    out = ["| " + " | ".join(headers) + " |", "|" + "---|" * len(headers)]
    out += ["| " + " | ".join(cell(c) for c in r) + " |" for r in rows]
    return "\n".join(out) + "\n"


def pages() -> list[tuple[Path, dict]]:
    out = []
    for p in kblib.topic_pages():
        fm, _ = kblib.split_front_matter(p.read_text(encoding="utf-8"))
        if fm:
            out.append((p, fm))
    return sorted(out, key=lambda x: (TOPIC_ORDER.index(x[1].get("topic", "curation"))
                                      if x[1].get("topic") in TOPIC_ORDER else 99, rel(x[0])))


def decisions() -> list[tuple[Path, dict, str]]:
    out = []
    for p in kblib.decision_records():
        fm, body = kblib.split_front_matter(p.read_text(encoding="utf-8"))
        out.append((p, fm or {}, kblib.h1(body) or p.stem))
    return out


def link_from(page_dir: Path, target: str) -> str:
    """A link to a KB path or URL, written relative to the page that shows it."""
    if target.startswith("https://"):
        return target
    path, _, frag = target.partition("#")
    rel_path = Path(*[".."] * len(page_dir.relative_to(KB_DIR).parts), path).as_posix()
    return rel_path + (f"#{frag}" if frag else "")


def render_kb_index() -> str:
    rows = []
    for p, fm in pages():
        if rel(p) == "README.md":
            continue
        target = rel(p).removesuffix("README.md") or rel(p)
        rows.append([f"[{target}]({rel(p)})", fm["summary"], fm["status"]])
    rows.append(["[decisions/](decisions/README.md)", "Decision records (MADR): what was decided and why", ""])
    return table(["Page", "What's in it", "Status"], rows)


def render_decision_index() -> str:
    rows = []
    for p, fm, title in decisions():
        num, _, name = title.partition(". ")
        rows.append([f"[{num}]({p.name})", name or title, str(fm.get("status", "")).capitalize()])
    return table(["#", "Decision", "Status"], rows)


def render_known_errors() -> str:
    page_dir = KB_DIR / "troubleshooting"
    rows = []
    for e in kblib.load_yaml(kblib.KNOWN_ERRORS)["errors"]:
        fix = e["fix"] + (" *(unverified)*" if e["status"] == "unverified" else "")
        src = e["source"]
        label = src.split("/")[-1].split("#")[0] if not src.startswith("https://") else "link"
        rows.append([e["symptom"], e["cause"], fix, f"[{label}]({link_from(page_dir, src)})"])
    return table(["Symptom", "Cause", "Fix", "Source"], rows)


def render_upstream(section: str) -> str:
    data = kblib.load_yaml(kblib.UPSTREAM)[section]
    third = "Suggested fix" if section == "docs_packaging" else "Why it matters"
    first = {"feature_gaps": "Gap", "api_asks": "Ask", "docs_packaging": "Item"}[section]
    rows = []
    for e in data:
        status = e["status"]
        if e.get("link"):
            status = f"[{status}]({e['link']})"
        if e.get("note"):
            status += f" ({e['note']})"
        rows.append([e["title"], e["evidence"], e.get("fix" if section == "docs_packaging" else "why", ""), status])
    return table([first, "Evidence", third, "Status"], rows)


def expert_links(e: dict) -> str:
    links = e.get("links", {})
    out = []
    if links.get("blog"):
        out.append(f"[blog]({links['blog']})")
    if links.get("youtube"):
        out.append(f"[YouTube]({links['youtube']})")
    if links.get("github"):
        out.append(f"[GitHub](https://github.com/{links['github']})")
    return ", ".join(out)


def render_experts(status: str) -> str:
    data = kblib.load_yaml(kblib.EXPERTS)
    rows = []
    for e in sorted(data["experts"], key=lambda e: (-kblib.expert_total(e), e["name"])):
        if e["status"] != status:
            continue
        if status == "nominated":
            issue = f"#{e['issue']}" if e.get("issue") else ""
            rows.append([e["name"], expert_links(e), issue, e.get("notes", "")])
            continue
        sc = e["scores"]
        score = f"{kblib.expert_total(e)} ({sc['relevance']}/{sc['depth']}/{sc['recency']}/{sc['track_record']}/{sc['feedability']})"
        latest = f"[{e['latest']['date']}]({e['latest']['url']})" if e.get("latest") else "none found"
        failed = [g for g, ok in e["gates"].items() if not ok]
        why = e.get("notes", "")
        if failed:
            why = f"Fails: {', '.join(failed)}. " + why
        rows.append([e["name"], e["affiliation"], expert_links(e), score, latest, why.strip()])
    if status == "nominated":
        return table(["Name", "Links", "Nomination", "Notes"], rows) if rows else "None waiting.\n"
    if not rows:
        return "None.\n"
    return table(["Name", "Affiliation", "Links", "Score (rel/depth/recency/record/feed)", "Latest AI post", "Notes"], rows)


def render_expert_balance() -> str:
    data = kblib.load_yaml(kblib.EXPERTS)
    tracked = [e for e in data["experts"] if e["status"] == "tracked"]
    counts: dict[str, int] = {}
    for e in tracked:
        counts[e["affiliation"]] = counts.get(e["affiliation"], 0) + 1
    parts = ", ".join(f"{n} {a}" for a, n in sorted(counts.items(), key=lambda x: -x[1]))
    by_status = {s: sum(1 for e in data["experts"] if e["status"] == s) for s in ("tracked", "watch", "declined", "nominated")}
    return (f"Last scored {data['reviewed']}: {by_status['tracked']} tracked ({parts or 'none'}), "
            f"{by_status['watch']} on the watch list, {by_status['declined']} declined, "
            f"{by_status['nominated']} nominated and waiting to be scored.\n")


def family_rows() -> list[dict]:
    return [p for p in kblib.load_yaml(kblib.FAMILY)["projects"] if not p.get("self")]


def family_link(p: dict) -> str:
    if not p.get("repo"):
        return f"{p['name']} (repo not linked yet)"
    path = p.get("kb_path", "docs/knowledge").strip("/")
    return f"[{p['name']}](https://github.com/{p['repo']}/tree/main/{path})"


def render_family() -> str:
    rows = [[family_link(p), p.get("role", "member"), p["focus"], "; ".join(p["owns"])] for p in family_rows()]
    return table(["Knowledge base", "Role", "Focus", "Source of truth for"], rows)


def render_llms_txt() -> str:
    cfg = kblib.kb_config()
    lines = [
        f"# {cfg['name']}: {cfg['title']}",
        "",
        *textwrap.wrap(cfg["tagline"], width=100, initial_indent="> ", subsequent_indent="> "),
        "",
        "The knowledge base is in docs/knowledge/. Every page starts with YAML front matter (title, summary,",
        "topic, status, last_reviewed) validated against docs/knowledge/schema/. Pages with status `plan`",
        "describe intended work, not facts, and claims marked *unverified* are not yet confirmed. To",
        "contribute, open a KB feedback or known-error issue; changes land only through reviewed pull requests.",
        "",
        "## Knowledge base",
        "",
    ]
    for p, fm in pages():
        lines.append(f"- [{fm['title']}](docs/knowledge/{rel(p)}): {fm['summary']} (status: {fm['status']})")
    lines += ["", "## Structured data", ""]
    for d in cfg.get("data", []):
        if (KB_DIR / d["path"]).is_file():
            lines.append(f"- [{d['name']}](docs/knowledge/{d['path']}): {d['text']}")
    lines += [
        "- [Schemas](docs/knowledge/schema/page.schema.json): JSON Schemas for page front matter and the YAML files above",
        "",
        "## Decisions",
        "",
    ]
    for p, fm, title in decisions():
        lines.append(f"- [{title}](docs/knowledge/decisions/{p.name}): {fm.get('status', '')}")
    lines += ["", "## Related knowledge bases", ""]
    for p in family_rows():
        lines.append(f"- {family_link(p)}: {p['focus']}. Source of truth for: {'; '.join(p['owns'])}")
    lines += [
        "",
        "## Optional",
        "",
        "- [Curator sources](docs/knowledge/sources.toml): the feeds and repos the weekly digest watches",
        "",
    ]
    return "\n".join(lines)


def fill_blocks(text: str, renderers: dict) -> str:
    def sub(m: re.Match) -> str:
        name = m.group("name")
        if name not in renderers:
            return m.group(0)
        return m.group(1) + renderers[name]() + m.group(4)
    return BLOCK.sub(sub, text)


def targets() -> dict[Path, str]:
    """Every generated file and its desired content."""
    out = {}
    jobs = {
        KB_DIR / "README.md": {"kb-index": render_kb_index, "family": render_family},
        KB_DIR / "decisions" / "README.md": {"decision-index": render_decision_index},
        KB_DIR / "troubleshooting" / "README.md": {"known-errors": render_known_errors},
        KB_DIR / "experts.md": {
            "experts-balance": render_expert_balance,
            **{f"experts-{s}": (lambda s=s: render_experts(s)) for s in ("tracked", "watch", "declined", "nominated")},
        },
        KB_DIR / "anthropic" / "upstream-contributions.md": {
            s: (lambda s=s: render_upstream(s)) for s in ("feature_gaps", "api_asks", "docs_packaging")
        },
    }
    for path, renderers in jobs.items():
        if not path.exists():  # optional pages, such as upstream asks, that a KB may not have
            continue
        out[path] = fill_blocks(path.read_text(encoding="utf-8"), renderers)
    out[kblib.LLMS_TXT] = render_llms_txt()
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="fail if any generated file is out of date")
    args = ap.parse_args()

    stale = []
    for path, content in targets().items():
        current = path.read_text(encoding="utf-8") if path.exists() else ""
        if current == content:
            continue
        stale.append(path.relative_to(kblib.ROOT).as_posix())
        if not args.check:
            path.write_text(content, encoding="utf-8")

    if args.check and stale:
        for s in stale:
            print(f"::error file={s}::out of date; run python3 scripts/kb/build.py and commit the result")
        return 1
    print("\n".join(f"updated {s}" for s in stale) or "everything up to date")
    return 0


if __name__ == "__main__":
    sys.exit(main())
