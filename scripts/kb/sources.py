"""Fetchers for the KB curator. Standard library only, so it runs on any CI runner."""

from __future__ import annotations

import json
import os
import tomllib
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

def _user_agent() -> str:
    """From this KB's kb.toml, so every KB sharing these scripts identifies itself."""
    kb_toml = os.path.join(os.path.dirname(__file__), "..", "..", "docs", "knowledge", "kb.toml")
    try:
        with open(kb_toml, "rb") as f:
            return tomllib.load(f).get("user_agent", "kb-curator")
    except OSError:
        return "kb-curator"


USER_AGENT = _user_agent()
GITHUB_API = "https://api.github.com"


@dataclass
class Item:
    title: str
    url: str
    date: datetime
    text: str = ""
    note: str = ""


def http_get(url: str, headers: dict | None = None) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, **(headers or {})})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read()


def github(path: str, params: dict | None = None):
    headers = {"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"}
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    url = f"{GITHUB_API}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    return json.loads(http_get(url, headers))


def parse_date(value: str) -> datetime:
    value = value.strip()
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        dt = parsedate_to_datetime(value)
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def first_line(text: str) -> str:
    return (text or "").strip().splitlines()[0] if (text or "").strip() else ""


def github_releases(src: dict, since: datetime) -> list[Item]:
    items = []
    for rel in github(f"/repos/{src['repo']}/releases", {"per_page": 30}):
        if rel.get("draft") or not rel.get("published_at"):
            continue
        date = parse_date(rel["published_at"])
        if date < since:
            continue
        items.append(Item(
            title=f"{src['repo']} {rel.get('name') or rel['tag_name']}",
            url=rel["html_url"],
            date=date,
            text=rel.get("body") or "",
            note="pre-release" if rel.get("prerelease") else "",
        ))
    return items


def github_commits(src: dict, since: datetime) -> list[Item]:
    params = {"since": since.strftime("%Y-%m-%dT%H:%M:%SZ"), "per_page": 50}
    if src.get("path"):
        params["path"] = src["path"]  # only commits touching this file or folder
    commits = github(f"/repos/{src['repo']}/commits", params)
    return [
        Item(
            title=first_line(c["commit"]["message"]),
            url=c["html_url"],
            date=parse_date(c["commit"]["committer"]["date"]),
            text=c["commit"]["message"],
        )
        for c in commits
    ]


def github_org_repos(src: dict, since: datetime) -> list[Item]:
    path = f"/users/{src['user']}/repos" if "user" in src else f"/orgs/{src['org']}/repos"
    items = []
    for repo in github(path, {"sort": "pushed", "per_page": 50}):
        created = parse_date(repo["created_at"])
        pushed = parse_date(repo["pushed_at"]) if repo.get("pushed_at") else created
        if pushed < since:
            continue
        items.append(Item(
            title=repo["full_name"] + (f": {repo['description']}" if repo.get("description") else ""),
            url=repo["html_url"],
            date=max(created, pushed),
            text=repo.get("description") or "",
            note="new repo" if created >= since else "updated",
        ))
    return items


def github_search(src: dict, since: datetime) -> list[Item]:
    query = f"{src['query']} created:>={since.date().isoformat()}"
    result = github("/search/repositories", {"q": query, "sort": "updated", "per_page": 30})
    return [
        Item(
            title=r["full_name"] + (f": {r['description']}" if r.get("description") else ""),
            url=r["html_url"],
            date=parse_date(r["created_at"]),
            text=r.get("description") or "",
            note=f"{r.get('stargazers_count', 0)} stars",
        )
        for r in result.get("items", [])
    ]


def github_issues(src: dict, since: datetime) -> list[Item]:
    query = f"repo:{src['repo']} updated:>={since.date().isoformat()}"
    result = github("/search/issues", {"q": query, "sort": "updated", "per_page": 30})
    items = []
    for i in result.get("items", []):
        created = parse_date(i["created_at"])
        kind = "PR" if "pull_request" in i else "issue"
        items.append(Item(
            title=f"{kind} #{i['number']}: {i['title']}",
            url=i["html_url"],
            date=parse_date(i["updated_at"]),
            text=i.get("body") or "",
            note=f"new {kind}" if created >= since else f"{i['state']}, updated",
        ))
    return items


def feed(src: dict, since: datetime) -> list[Item]:
    root = ET.fromstring(http_get(src["url"]))
    atom = "{http://www.w3.org/2005/Atom}"
    items = []
    for node in root.iter():
        if node.tag == "item":  # RSS
            title = node.findtext("title", "")
            link = node.findtext("link", "")
            date = node.findtext("pubDate") or node.findtext("{http://purl.org/dc/elements/1.1/}date")
            text = node.findtext("description", "")
        elif node.tag == f"{atom}entry":
            title = node.findtext(f"{atom}title", "")
            link_el = node.find(f"{atom}link")
            link = link_el.get("href", "") if link_el is not None else ""
            date = node.findtext(f"{atom}updated") or node.findtext(f"{atom}published")
            text = node.findtext(f"{atom}summary", "")
        else:
            continue
        if not date:
            continue
        dt = parse_date(date)
        if dt >= since:
            items.append(Item(title=title.strip(), url=link.strip(), date=dt, text=text or ""))
    return items


def zendesk(src: dict, since: datetime) -> list[Item]:
    base = src["url"].rstrip("/")
    data = json.loads(http_get(
        f"{base}/api/v2/help_center/articles.json?sort_by=updated_at&sort_order=desc&per_page=50"))
    items = []
    for art in data.get("articles", []):
        date = parse_date(art["updated_at"])
        if date < since:
            break
        created = parse_date(art["created_at"])
        items.append(Item(
            title=art["title"],
            url=art["html_url"],
            date=date,
            text=art.get("body") or "",
            note="new article" if created >= since else "updated",
        ))
    return items


FETCHERS = {
    "github_releases": github_releases,
    "github_commits": github_commits,
    "github_org_repos": github_org_repos,
    "github_user_repos": github_org_repos,
    "github_search": github_search,
    "github_issues": github_issues,
    "feed": feed,
    "zendesk": zendesk,
}
