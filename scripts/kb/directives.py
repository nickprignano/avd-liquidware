#!/usr/bin/env python3
"""Read the family's maintainer directives (decision 0008) and act on them.

    python3 scripts/kb/directives.py gate <workflow>   # is this kb-* workflow paused here?
    python3 scripts/kb/directives.py list              # the active directives in this KB's scope
    python3 scripts/kb/directives.py sync-issues       # open/close kb-directive pointer issues

The directives live in the hub: the family.yaml project with role reference. In the hub itself
they're read from the working tree; a sibling reads the hub's public file with no credential. A
missing file means no directives yet. `gate` also honours a KB_PAUSED repository variable (passed in
the environment), which stops this repo's automated workflows even when the hub can't be read.
`gate` writes paused=true|false to $GITHUB_OUTPUT when it's set.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import date
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kblib  # noqa: E402

DIRECTIVES = kblib.DIRECTIVES
LABEL = "kb-directive"
API = "https://api.github.com"


def hub(data: dict | None = None) -> dict | None:
    data = kblib.family() if data is None else data
    for p in data.get("projects", []):
        if p.get("role") == "reference":
            return p
    return None


def self_id(data: dict | None = None) -> str | None:
    data = kblib.family() if data is None else data
    return next((p["id"] for p in data.get("projects", []) if p.get("self")), None)


def hub_url(project: dict) -> str:
    return f"https://raw.githubusercontent.com/{project['repo']}/HEAD/{kblib.kb_path(project)}/directives.yaml"


def fetch(url: str) -> str | None:
    req = urllib.request.Request(url, headers={"User-Agent": kblib.kb_config().get("user_agent", "kb-curator")})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def load(family: dict | None = None, fetcher=fetch) -> tuple[list[dict], str]:
    """All directives, and where they came from."""
    family = kblib.family() if family is None else family
    h = hub(family)
    if h is None or h.get("self") or not h.get("repo"):
        if not DIRECTIVES.exists():
            return [], kblib.rel(DIRECTIVES)
        return (kblib.load_yaml(DIRECTIVES) or {}).get("directives", []), kblib.rel(DIRECTIVES)
    url = hub_url(h)
    text = fetcher(url)
    return ((yaml.safe_load(text) or {}).get("directives", []) if text else []), url


def is_active(d: dict, today: date) -> bool:
    until = d.get("until")
    return until is None or date.fromisoformat(str(until)) >= today


def in_scope(d: dict, kb_id: str | None) -> bool:
    scope = d.get("scope", [])
    return "all" in scope or (kb_id is not None and kb_id in scope)


def applicable(directives: list[dict], kb_id: str | None, today: date) -> list[dict]:
    return [d for d in directives if is_active(d, today) and in_scope(d, kb_id)]


def pausing(directives: list[dict], workflow: str, kb_id: str | None, today: date) -> list[dict]:
    return [d for d in applicable(directives, kb_id, today)
            if {"all", workflow} & set(d.get("pause", []))]


def expired(directives: list[dict], today: date) -> list[dict]:
    return [d for d in directives if not is_active(d, today)]


def gate(workflow: str, today: date, env=os.environ, loader=load) -> tuple[bool, str]:
    if env.get("KB_PAUSED", "").strip().lower() in ("true", "1", "yes"):
        return True, "KB_PAUSED is set on this repo"
    try:
        directives, source = loader()
    except Exception as exc:  # the hub can't be read: run as normal, KB_PAUSED is the stop
        return False, f"couldn't read directives ({type(exc).__name__}); running"
    hits = pausing(directives, workflow, self_id(), today)
    if hits:
        return True, "paused by " + ", ".join(d["id"] for d in hits) + f" in {source}"
    return False, "no directive pauses it"


def issue_title(d: dict) -> str:
    text = d["directive"]
    return f"Directive {d['id']}: " + (text if len(text) <= 60 else text[:57] + "...")


def issue_body(d: dict, source: str) -> str:
    lines = [f"> {d['directive']}", "",
             f"- Scope: {', '.join(d['scope'])}",
             f"- Pauses: {', '.join(d.get('pause', [])) or 'nothing'}",
             f"- Until: {d.get('until', 'removed')}",
             f"- Opened: {d['opened']}",
             f"- Source: {source}", "",
             "A pointer to a maintainer directive for this KB (decision 0008). It closes by itself when "
             "the directive is removed or expires. Directives never override the guardrails."]
    return "\n".join(lines)


def api(method: str, path: str, body: dict | None = None):
    req = urllib.request.Request(f"{API}{path}", method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Accept": "application/vnd.github+json",
                                          "Authorization": f"Bearer {os.environ['GITHUB_TOKEN']}",
                                          "User-Agent": kblib.kb_config().get("user_agent", "kb-curator")})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r) if r.status != 204 else None


def sync_issues(repo: str, today: date) -> list[str]:
    directives, source = load()
    want = {d["id"]: d for d in applicable(directives, self_id(), today)}
    open_issues = api("GET", f"/repos/{repo}/issues?labels={LABEL}&state=open&per_page=100")
    have = {}
    for i in open_issues:
        title = i["title"]
        if title.startswith("Directive ") and ":" in title:
            have[title[len("Directive "):title.index(":")]] = i["number"]
    done = []
    for did, d in want.items():
        if did not in have:
            n = api("POST", f"/repos/{repo}/issues",
                    {"title": issue_title(d), "body": issue_body(d, source), "labels": [LABEL]})["number"]
            done.append(f"opened #{n} for {did}")
    for did, n in have.items():
        if did not in want:
            api("PATCH", f"/repos/{repo}/issues/{n}", {"state": "closed", "state_reason": "completed"})
            done.append(f"closed #{n} for {did}")
    return done


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("gate")
    g.add_argument("workflow")
    sub.add_parser("list")
    sub.add_parser("sync-issues")
    args = ap.parse_args()
    today = date.today()
    if args.cmd == "gate":
        paused, why = gate(args.workflow, today)
        print(f"{args.workflow}: {'paused' if paused else 'runs'} ({why})")
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as f:
                f.write(f"paused={'true' if paused else 'false'}\n")
        return 0
    if args.cmd == "list":
        directives, source = load()
        active = applicable(directives, self_id(), today)
        print(f"{len(active)} active directive(s) for this KB, from {source}")
        for d in active:
            print(f"- {d['id']}: {d['directive']} (pause: {', '.join(d.get('pause', [])) or 'none'}; "
                  f"until: {d.get('until', 'removed')})")
        return 0
    for line in sync_issues(os.environ["GITHUB_REPOSITORY"], today) or ["nothing to change"]:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
