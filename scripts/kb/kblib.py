"""Shared helpers for the knowledge base scripts: paths, front matter, YAML data and anchors.

Needs PyYAML (and jsonschema for validate.py): pip install -r scripts/kb/requirements.txt
"""

from __future__ import annotations

import re
import tomllib
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
KB_DIR = ROOT / "docs" / "knowledge"
SCHEMA_DIR = KB_DIR / "schema"
DECISIONS_DIR = KB_DIR / "decisions"
LLMS_TXT = ROOT / "llms.txt"

KNOWN_ERRORS = KB_DIR / "troubleshooting" / "known-errors.yaml"
UPSTREAM = KB_DIR / "anthropic" / "upstream.yaml"
FIELD_REPORTS = KB_DIR / "field-reports.yaml"
EXPERTS = KB_DIR / "experts.yaml"
SOURCES = KB_DIR / "sources.toml"
FAMILY = KB_DIR / "family.yaml"
KB_TOML = KB_DIR / "kb.toml"
DIRECTIVES = KB_DIR / "directives.yaml"
MAX_DIRECTIVES = 5

# The experts study (experts.md): five scores of 0-3, plus pass/fail gates.
TRACK_AT = 10
WATCH_AT = 6

# Files under docs/knowledge/ that aren't topic pages.
NOT_PAGES = {"decisions/README.md", "decisions/template.md"}

FRONT_MATTER = re.compile(r"\A---\n(.*?)\n---\n", re.S)
DECISION_FILE = re.compile(r"^\d{4}-[a-z0-9-]+\.md$")


def kb_config() -> dict:
    """This KB's identity from kb.toml: name, title, tagline, user agent, topic order, data files."""
    with KB_TOML.open("rb") as f:
        return tomllib.load(f)


def rel(path: Path) -> str:
    return path.relative_to(KB_DIR).as_posix()


def topic_pages() -> list[Path]:
    """Every Markdown page that needs page front matter (decision records excluded)."""
    return sorted(
        p for p in KB_DIR.rglob("*.md")
        if not rel(p).startswith("decisions/") and rel(p) not in NOT_PAGES
    )


def decision_records() -> list[Path]:
    return sorted(p for p in DECISIONS_DIR.glob("*.md") if DECISION_FILE.match(p.name))


def split_front_matter(text: str) -> tuple[dict | None, str]:
    """Return (front matter dict or None, body). Dates stay strings so JSON Schema can check them."""
    m = FRONT_MATTER.match(text)
    if not m:
        return None, text
    data = yaml.load(m.group(1), Loader=_StringDateLoader) or {}
    return data, text[m.end():]


def h1(body: str) -> str | None:
    for line in body.splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return None


def load_yaml(path: Path):
    return yaml.load(path.read_text(encoding="utf-8"), Loader=_StringDateLoader)


def dump_yaml(data) -> str:
    return yaml.dump(data, Dumper=_Dumper, sort_keys=False, width=100, allow_unicode=True)


def yaml_header(path: Path) -> str:
    """The leading comment block of a YAML file, kept when the file is rewritten."""
    lines = []
    for line in path.read_text(encoding="utf-8").splitlines(keepends=True):
        if line.startswith("#") or not line.strip():
            lines.append(line)
        else:
            break
    return "".join(lines)


def strip_code(text: str) -> str:
    """Remove fenced code blocks and inline code so links and markers inside them are ignored."""
    text = re.sub(r"^```.*?^```", "", text, flags=re.S | re.M)
    return re.sub(r"`[^`\n]*`", "", text)


def anchors(body: str) -> set[str]:
    """GitHub-style heading anchors for a Markdown body."""
    seen: dict[str, int] = {}
    out = set()
    for line in strip_fences(body).splitlines():
        m = re.match(r"^#{1,6}\s+(.*?)\s*#*\s*$", line)
        if not m:
            continue
        slug = re.sub(r"[^\w\- ]", "", m.group(1).strip().lower()).replace(" ", "-")
        n = seen.get(slug, 0)
        seen[slug] = n + 1
        out.add(slug if n == 0 else f"{slug}-{n}")
    return out


def strip_fences(text: str) -> str:
    return re.sub(r"^```.*?^```", "", text, flags=re.S | re.M)


class _StringDateLoader(yaml.SafeLoader):
    pass


# Keep YYYY-MM-DD as plain strings instead of datetime.date.
_StringDateLoader.yaml_implicit_resolvers = {
    k: [(tag, rx) for tag, rx in v if tag != "tag:yaml.org,2002:timestamp"]
    for k, v in yaml.SafeLoader.yaml_implicit_resolvers.items()
}


class _Dumper(yaml.SafeDumper):
    pass


_Dumper.add_representer(
    str,
    lambda d, s: d.represent_scalar("tag:yaml.org,2002:str", s, style=">" if len(s) > 90 else None),
)


def family() -> dict:
    return load_yaml(FAMILY) or {}


def siblings(data: dict | None = None) -> list[dict]:
    """Sibling KBs whose repo is known; a row without a repo isn't linked yet. Observers aren't watched."""
    data = family() if data is None else data
    return [p for p in data.get("projects", [])
            if not p.get("self") and p.get("repo") and p.get("role") != "observer"]


def kb_path(project: dict) -> str:
    return project.get("kb_path", "docs/knowledge").strip("/")


def expert_total(e: dict) -> int:
    return sum((e.get("scores") or {}).values())


def expert_tier(e: dict) -> str:
    """The status an expert's gates and scores give, by the rules in experts.md."""
    g = e.get("gates") or {}
    if not (g.get("identity") and g.get("original")):
        return "declined"
    total = expert_total(e)
    if g.get("recent") and g.get("feed") and total >= TRACK_AT:
        return "tracked"
    return "watch" if total >= WATCH_AT else "declined"
