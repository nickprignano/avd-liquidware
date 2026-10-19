"""Tests for the knowledge base scripts. Run: python3 -m unittest discover -s scripts/kb"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build  # noqa: E402
import feedback  # noqa: E402
import freshness  # noqa: E402
import kblib  # noqa: E402

SAFE = "### Public-safe\n\n- [X] I removed API keys, account and workspace IDs, names, domains, emails, IP addresses and secrets.\n"

FEEDBACK_BODY = """### Outcome

Broke or gave the wrong result

### Page

docs/knowledge/stratusphere/appliances.md

### What happened

The subnet fix needed a different block name.

### Versions

_No response_

### Evidence

_No response_

""" + SAFE

KNOWN_ERROR_BODY = """### Symptom

`invalid_request_error` on `messages.create`

### Cause

Renamed in an SDK release.

### Fix

Use the new argument name.

### Source

https://example.com/changelog

### Versions

anthropic 0.69.0

### Confidence

Fix worked once; the cause is a guess

""" + SAFE


class TempData(unittest.TestCase):
    """Point the data files at temporary copies so tests never touch the real KB."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.patches = []
        for name in ("KNOWN_ERRORS", "FIELD_REPORTS", "EXPERTS"):
            src = getattr(kblib, name)
            dst = self.tmp / src.name
            shutil.copy(src, dst)
            p = mock.patch.object(kblib, name, dst)
            p.start()
            self.patches.append(p)

    def tearDown(self):
        for p in self.patches:
            p.stop()
        shutil.rmtree(self.tmp)


class FeedbackTests(TempData):
    def test_parse_form(self):
        fields = feedback.parse_form(FEEDBACK_BODY)
        self.assertEqual(fields["Outcome"], "Broke or gave the wrong result")
        self.assertEqual(fields["Versions"], "")

    def test_field_report(self):
        issue = {"number": 7, "body": FEEDBACK_BODY, "labels": [{"name": "kb-feedback"}]}
        title, _ = feedback.handle(issue, "2026-10-16")
        self.assertIn("broke on stratusphere/appliances.md", title)
        report = kblib.load_yaml(kblib.FIELD_REPORTS)["reports"][-1]
        self.assertEqual(report["page"], "stratusphere/appliances.md")
        self.assertNotIn("versions", report)
        with self.assertRaises(feedback.FeedbackError):
            feedback.handle(issue, "2026-10-16")  # same issue twice

    def test_known_error(self):
        issue = {"number": 8, "body": KNOWN_ERROR_BODY, "labels": [{"name": "kb-known-error"}]}
        feedback.handle(issue, "2026-10-16")
        entry = kblib.load_yaml(kblib.KNOWN_ERRORS)["errors"][-1]
        self.assertEqual(entry["status"], "unverified")
        self.assertEqual(entry["source"], "https://example.com/changelog")
        self.assertTrue(kblib.KNOWN_ERRORS.read_text().startswith("# Known errors catalog"))

    def test_rejects_unticked_and_missing_page(self):
        unticked = FEEDBACK_BODY.replace("- [X]", "- [ ]")
        with self.assertRaises(feedback.FeedbackError):
            feedback.handle({"number": 9, "body": unticked, "labels": ["kb-feedback"]}, "2026-10-16")
        bad_page = FEEDBACK_BODY.replace("stratusphere/appliances.md", "../../etc/passwd")
        with self.assertRaises(feedback.FeedbackError):
            feedback.handle({"number": 10, "body": bad_page, "labels": ["kb-feedback"]}, "2026-10-16")


NOMINATION_BODY = """### Name

Example Person

### Blog

https://example.com/blog

### YouTube channel

_No response_

### GitHub username

@octocat

### Why follow them

Writes detailed posts on building agents.

""" + SAFE.replace("API keys, account and workspace IDs, names, domains, emails, IP addresses and secrets",
                   "only included public professional links")


class NominationTests(TempData):
    def test_nomination(self):
        issue = {"number": 12, "body": NOMINATION_BODY, "labels": ["kb-source"]}
        title, _ = feedback.handle(issue, "2026-10-17")
        self.assertIn("Example Person", title)
        entry = kblib.load_yaml(kblib.EXPERTS)["experts"][-1]
        self.assertEqual(entry["status"], "nominated")
        self.assertEqual(entry["links"], {"blog": "https://example.com/blog", "github": "octocat"})
        with self.assertRaises(feedback.FeedbackError):
            feedback.handle(issue, "2026-10-17")  # same issue twice

    def test_rejects_bad_links(self):
        bad = NOMINATION_BODY.replace("https://example.com/blog", "javascript:alert(1)")
        with self.assertRaises(feedback.FeedbackError):
            feedback.handle({"number": 13, "body": bad, "labels": ["kb-source"]}, "2026-10-17")


class ExpertTierTests(unittest.TestCase):
    def entry(self, total_scores, **gates):
        g = {"original": True, "recent": True, "feed": True, "identity": True, **gates}
        names = ["relevance", "depth", "recency", "track_record", "feedability"]
        return {"gates": g, "scores": dict(zip(names, total_scores))}

    def test_tiers(self):
        self.assertEqual(kblib.expert_tier(self.entry([2, 2, 2, 2, 2])), "tracked")
        self.assertEqual(kblib.expert_tier(self.entry([3, 3, 3, 3, 3], feed=False)), "watch")
        self.assertEqual(kblib.expert_tier(self.entry([2, 1, 1, 1, 1])), "watch")
        self.assertEqual(kblib.expert_tier(self.entry([1, 1, 1, 1, 1])), "declined")
        self.assertEqual(kblib.expert_tier(self.entry([3, 3, 3, 3, 3], identity=False)), "declined")

    def test_digest_yield(self):
        body = "### Blog A → `docs/knowledge/x.md`\n- [x] [one](https://a/1)\n- [ ] [two](https://a/2)\n### Blog B\n- [ ] [b](https://b)\n"
        counts = freshness.digest_yield([{"createdAt": "2026-10-12T13:00:00Z", "body": body},
                                         {"createdAt": "2025-01-01T13:00:00Z", "body": body}], date(2026, 9, 1))
        self.assertEqual(counts, {"Blog A": [1, 2], "Blog B": [0, 1]})


class FreshnessTests(TempData):
    def test_stale_and_reported(self):
        issue = {"number": 11, "body": FEEDBACK_BODY, "labels": ["kb-feedback"]}
        feedback.handle(issue, "2026-10-16")
        sections = freshness.collect(90, date(2027, 6, 1))
        self.assertTrue(any("stratusphere/appliances.md" in i for i in sections["Reported broken or outdated"]))
        self.assertTrue(sections["Stale"])
        self.assertFalse(any("roadmap/README.md" in i for i in sections["Stale"]))  # plan pages skip


class BuildTests(unittest.TestCase):
    def test_generated_files_up_to_date(self):
        stale = [p for p, c in build.targets().items() if p.read_text(encoding="utf-8") != c]
        self.assertEqual(stale, [], "run python3 scripts/kb/build.py")

    def test_link_from(self):
        page_dir = kblib.KB_DIR / "troubleshooting"
        self.assertEqual(build.link_from(page_dir, "agents/README.md#x"), "../agents/README.md#x")
        self.assertEqual(build.link_from(page_dir, "https://example.com"), "https://example.com")


class FamilyTests(unittest.TestCase):
    FAMILY = {"format_version": 1, "projects": [
        {"id": "us", "name": "Us", "self": True, "focus": "x", "owns": ["x"]},
        {"id": "sib", "name": "Sib", "repo": "octo/sib", "kb_path": "kb", "focus": "y", "owns": ["y"]},
        {"id": "later", "name": "Later", "focus": "z", "owns": ["z"]},
    ]}

    def setUp(self):
        p = mock.patch.object(kblib, "family", lambda: self.FAMILY)
        p.start()
        self.addCleanup(p.stop)

    def test_siblings_need_a_repo(self):
        self.assertEqual([p["name"] for p in kblib.siblings()], ["Sib"])

    def test_family_items(self):
        def private(project):
            raise OSError("404")

        self.assertEqual(freshness.family_items(lambda p: {"format_version": 1}),
                         ["Later: repo not linked yet; add it to family.yaml, then its sources"])
        self.assertTrue(any("family format 2" in i for i in freshness.family_items(lambda p: {"format_version": 2})))
        self.assertTrue(any("couldn't read" in i for i in freshness.family_items(private)))

    def test_validate_wants_sibling_sources(self):
        import validate
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp)
        (tmp / "sources.toml").write_text('[[source]]\nname = "a"\nkind = "github_commits"\nrepo = "octo/sib"\npath = "kb"\n')
        validate.errors.clear()
        with mock.patch.object(kblib, "SOURCES", tmp / "sources.toml"), mock.patch.object(validate, "ROOT", Path("/")):
            validate.check_family()
        self.assertEqual(len(validate.errors), 1)
        self.assertIn("kb/decisions", validate.errors[0])
        validate.errors.clear()


class DirectiveTests(unittest.TestCase):
    TODAY = date(2026, 10, 18)
    FAMILY = {"format_version": 1, "projects": [
        {"id": "sib", "name": "Sib", "self": True, "focus": "y", "owns": ["y"]},
        {"id": "hub", "name": "Hub", "repo": "octo/hub", "role": "reference", "focus": "x", "owns": ["x"]},
        {"id": "quiet", "name": "Private layer", "role": "observer", "focus": "z", "owns": ["z"]},
    ]}
    DIRECTIVES = [
        {"id": "d-20261018-1", "directive": "Pause the digest.", "scope": ["all"], "pause": ["kb-curator"],
         "opened": "2026-10-18"},
        {"id": "d-20261018-2", "directive": "Only the hub.", "scope": ["hub"], "pause": ["all"], "opened": "2026-10-18"},
        {"id": "d-20261001-1", "directive": "Old.", "scope": ["all"], "pause": ["all"], "until": "2026-10-10",
         "opened": "2026-10-01"},
    ]

    def setUp(self):
        import directives
        self.d = directives
        p = mock.patch.object(kblib, "family", lambda: self.FAMILY)
        p.start()
        self.addCleanup(p.stop)

    def test_sibling_reads_the_hub(self):
        seen = []
        self.d.load(fetcher=lambda url: seen.append(url) or "directives: []\n")
        self.assertEqual(seen, ["https://raw.githubusercontent.com/octo/hub/HEAD/docs/knowledge/directives.yaml"])
        self.assertEqual(self.d.load(fetcher=lambda url: None)[0], [])

    def test_scope_pause_and_expiry(self):
        active = self.d.applicable(self.DIRECTIVES, "sib", self.TODAY)
        self.assertEqual([x["id"] for x in active], ["d-20261018-1"])
        self.assertTrue(self.d.pausing(self.DIRECTIVES, "kb-curator", "sib", self.TODAY))
        self.assertFalse(self.d.pausing(self.DIRECTIVES, "kb-freshness", "sib", self.TODAY))
        self.assertTrue(self.d.pausing(self.DIRECTIVES, "kb-freshness", "hub", self.TODAY))
        self.assertEqual([x["id"] for x in self.d.expired(self.DIRECTIVES, self.TODAY)], ["d-20261001-1"])

    def test_gate(self):
        loader = lambda: (self.DIRECTIVES, "hub")  # noqa: E731
        self.assertTrue(self.d.gate("kb-curator", self.TODAY, env={}, loader=loader)[0])
        self.assertFalse(self.d.gate("kb-freshness", self.TODAY, env={}, loader=loader)[0])
        self.assertTrue(self.d.gate("kb-freshness", self.TODAY, env={"KB_PAUSED": "true"}, loader=loader)[0])

        def broken():
            raise OSError("offline")
        self.assertFalse(self.d.gate("kb-curator", self.TODAY, env={}, loader=broken)[0])

    def test_observers_are_not_watched(self):
        self.assertEqual(kblib.siblings(), [{"id": "hub", "name": "Hub", "repo": "octo/hub", "role": "reference",
                                             "focus": "x", "owns": ["x"]}])
        self.assertEqual(freshness.family_items(lambda p: {"format_version": 1}), [])

    def test_schema_and_active_limit(self):
        import validate
        v = validate.schema("directive.schema.json")
        self.assertEqual(list(v.iter_errors({"directives": self.DIRECTIVES})), [])
        self.assertTrue(list(v.iter_errors({"directives": [{**self.DIRECTIVES[0], "reason": "why"}]})))
        self.assertTrue(list(v.iter_errors({"directives": [{**self.DIRECTIVES[0], "directive": "x" * 281}]})))
        fam = validate.schema("family.schema.json")
        observer = {"id": "q", "name": "Q", "role": "observer", "repo": "octo/q", "focus": "z", "owns": ["z"]}
        self.assertTrue(list(fam.iter_errors({"format_version": 1, "projects": [observer]})))
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp)
        many = [{**self.DIRECTIVES[0], "id": f"d-20261018-{i}"} for i in range(6)]
        kblib.Path(tmp / "directives.yaml").write_text(kblib.dump_yaml({"directives": many}))
        validate.errors.clear()
        with mock.patch.object(kblib, "DIRECTIVES", tmp / "directives.yaml"), mock.patch.object(validate, "ROOT", Path("/")):
            validate.check_directives(self.TODAY)
        self.assertEqual(len(validate.errors), 1)
        self.assertIn("6 directives are active", validate.errors[0])
        validate.errors.clear()


class ExportTests(unittest.TestCase):
    """The 2ndbrain-public export builds, validates and passes its own tests. Skipped in the template."""

    def exporter(self):
        try:
            import export_template
        except ImportError:
            self.skipTest("no exporter here")
        if not export_template.MANIFEST.exists():
            self.skipTest("no template manifest here")
        return export_template

    def test_export_is_clean(self):
        export_template = self.exporter()
        out = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, out)
        export_template.export(out)
        for cmd in (["scripts/kb/validate.py"], ["scripts/kb/build.py", "--check"],
                    ["-m", "unittest", "discover", "-s", "scripts/kb"]):
            r = subprocess.run([sys.executable, *cmd], cwd=out, capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, f"{' '.join(cmd)} failed in the export:\n{r.stdout}{r.stderr}")

    def test_replace_that_no_longer_matches_fails(self):
        export_template = self.exporter()
        out = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, out)
        (out / "a.md").write_text("hello")
        with self.assertRaises(export_template.ExportError):
            export_template.apply_replacements({"replace": [{"file": "a.md", "find": "gone", "replace": "x"}]}, out)


class AnchorTests(unittest.TestCase):
    def test_github_slugs(self):
        body = "# A\n## Post-deployment checks with Playwright\n## 8. Deployment troubleshooting\n## A\n"
        self.assertEqual(kblib.anchors(body), {
            "a", "post-deployment-checks-with-playwright", "8-deployment-troubleshooting", "a-1"})


if __name__ == "__main__":
    unittest.main()
