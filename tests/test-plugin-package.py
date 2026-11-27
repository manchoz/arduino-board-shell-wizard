# SPDX-License-Identifier: MPL-2.0
"""Hardware-free package checks using disposable Git repositories."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parent.parent
SKILL = ".agents/skills/arduino-board-provision/"
IDENTITY = {
    "name": "arduino-board-shell-wizard",
    "version": "0.3.0",
    "description": "Disposable package fixture",
    "author": {"name": "fixture"},
    "license": "MPL-2.0",
}
FILES = [
    "board-host.sh", "board-host.ps1", "board/board-common.sh",
    "board/board-request.sh", "board/setup-arduino-board.sh",
    "board/reset-arduino-board.sh", "host/board-ssh.sh", "host/board-ssh.ps1",
    "AGENTS.md", "README.md", "LICENSE", "docs/adb.md", "docs/usage.md",
    "docs/unattended.md", "docs/technical.md", "docs/agent-workspace.md",
    "docs/manual-transfer.md", "docs/plugin-distribution.md", "docs/privacy.md",
]


class PluginPackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="arduino-package-test-")
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name) / "repo with spaces"
        self.repo.mkdir()
        for name in FILES:
            self.write(name, "#!/usr/bin/env bash\n# fixture\n" if name.endswith(".sh") else "fixture\n")
        self.write(".gitattributes", "*.sh text eol=lf\n")
        self.write(SKILL + "SKILL.md", "---\nname: arduino-board-provision\ndescription: Fixture\n---\nUse fixtures.\n")
        self.write(SKILL + "agents/openai.yaml", "interface:\n  display_name: Fixture\n")
        self.native = {**IDENTITY, "skills": "./.agents/skills/", "requires_local_executor": True,
                       "interface": {"displayName": "Fixture", "category": "Productivity"}}
        self.write_json(".codex-plugin/plugin.json", self.native)
        self.write_json(".claude-plugin/plugin.json", {**IDENTITY, "skills": "./.agents/skills/"})
        for name in [".agents/plugins/marketplace.json", ".claude-plugin/marketplace.json"]:
            self.write_json(name, {"name": "fixture-marketplace", "plugins": []})
        (self.repo / "scripts").mkdir()
        shutil.copyfile(ROOT / "scripts/package-plugin.py", self.repo / "scripts/package-plugin.py")
        self.git("init", "-q")
        self.git("config", "user.name", "Package Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "core.autocrlf", "true")
        self.commit()
        self.output = Path(self.temporary.name) / "bundle with spaces.zip"

    def write(self, name, text):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="\n")

    def write_json(self, name, value):
        self.write(name, json.dumps(value) + "\n")

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.repo), *args], check=True, capture_output=True).stdout

    def commit(self):
        self.git("add", ".")
        self.git("commit", "-qm", "package fixture")

    def package(self, ref="HEAD"):
        return subprocess.run([sys.executable, str(self.repo / "scripts/package-plugin.py"),
                               "--ref", ref, "--output", str(self.output)], capture_output=True)

    def test_complete_bundle(self):
        self.write("docs/skill-publication-plan.local.md", "untracked fixture marker\n")
        self.write("README.md", "uncommitted fixture marker\n")
        result = self.package()
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        with zipfile.ZipFile(self.output) as archive:
            names = archive.namelist()
            self.assertEqual(len(names), len(set(names)))
            for name in FILES:
                self.assertEqual(archive.read(name), self.git("show", "HEAD:" + name))
            for name in [SKILL + "SKILL.md", SKILL + "agents/openai.yaml"]:
                self.assertEqual(archive.read(name), archive.read(name.replace(".agents/skills/", "skills/", 1)))
            self.assertNotIn("docs/skill-publication-plan.local.md", names)
            self.assertFalse(any(name.startswith(".git/") for name in names))
            self.assertNotIn(b"\r", archive.read("board-host.sh"))
            manifest = json.loads(archive.read("plugin.json"))
            for name, value in IDENTITY.items():
                self.assertEqual(manifest[name], value)
            self.assertEqual(manifest["$schema"], "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json")
            self.assertTrue(manifest["extensions"]["com.openai"]["requires_local_executor"])
            self.assertEqual(json.loads(archive.read(".claude-plugin/plugin.json"))["skills"], "./skills/")

    def test_missing_payload_fails_without_overwriting_output(self):
        self.git("rm", "board/board-request.sh")
        self.git("commit", "-qm", "missing fixture")
        self.output.write_bytes(b"existing fixture output")
        result = self.package()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"board/board-request.sh", result.stderr)
        self.assertEqual(self.output.read_bytes(), b"existing fixture output")

    def test_mismatched_manifest_fails(self):
        self.write_json(".claude-plugin/plugin.json", {**IDENTITY, "version": "9.0.0", "skills": "./.agents/skills/"})
        self.commit()
        result = self.package()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"version", result.stderr)
        self.assertFalse(self.output.exists())

    def test_ref_selects_committed_snapshot(self):
        first = self.git("rev-parse", "HEAD").decode().strip()
        self.write("README.md", "new committed fixture\n")
        self.commit()
        result = self.package(first)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        with zipfile.ZipFile(self.output) as archive:
            self.assertEqual(archive.read("README.md"), b"fixture\n")

    def test_invalid_ref_fails(self):
        self.assertNotEqual(self.package("--remote=fixture").returncode, 0)
        self.assertFalse(self.output.exists())

    def test_generated_member_collision_fails(self):
        self.write("plugin.json", "{}\n")
        self.commit()
        self.assertNotEqual(self.package().returncode, 0)
        self.assertFalse(self.output.exists())

    def test_case_variant_skill_collision_fails(self):
        self.write("Skills/arduino-board-provision/SKILL.md", "case collision fixture\n")
        self.commit()
        result = self.package()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"generated portable members", result.stderr)
        self.assertFalse(self.output.exists())

    def test_missing_manifest_name_fails(self):
        for name in [".codex-plugin/plugin.json", ".claude-plugin/plugin.json"]:
            manifest = json.loads((self.repo / name).read_text(encoding="utf-8"))
            del manifest["name"]
            self.write_json(name, manifest)
        self.commit()
        result = self.package()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"name", result.stderr)
        self.assertFalse(self.output.exists())

    def test_invalid_manifest_names_fail(self):
        invalid = [None, "", 0, "invalid name", "Upper", "../invalid", "a" * 65,
                   "two--hyphens", "two..dots"]
        for index, value in enumerate(invalid):
            with self.subTest(value=value):
                for name in [".codex-plugin/plugin.json", ".claude-plugin/plugin.json"]:
                    manifest = json.loads((self.repo / name).read_text(encoding="utf-8"))
                    manifest["name"] = value
                    self.write_json(name, manifest)
                self.commit()
                self.output = Path(self.temporary.name) / ("invalid-name-" + str(index) + ".zip")
                result = self.package()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(b"name", result.stderr)
                self.assertFalse(self.output.exists())

    def test_valid_manifest_name_boundaries(self):
        for index, value in enumerate(["x", "a" * 64, "board.tool-2"]):
            with self.subTest(value=value):
                for name in [".codex-plugin/plugin.json", ".claude-plugin/plugin.json"]:
                    manifest = json.loads((self.repo / name).read_text(encoding="utf-8"))
                    manifest["name"] = value
                    self.write_json(name, manifest)
                self.commit()
                self.output = Path(self.temporary.name) / ("valid-name-" + str(index) + ".zip")
                result = self.package()
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                with zipfile.ZipFile(self.output) as archive:
                    self.assertEqual(json.loads(archive.read("plugin.json"))["name"], value)

    def test_symlink_payload_fails(self):
        self.write("fixture-link", "../outside-fixture\n")
        blob = self.git("hash-object", "-w", "fixture-link").decode().strip()
        self.git("update-index", "--cacheinfo", "120000," + blob + ",board/board-request.sh")
        self.git("commit", "-qm", "symlink fixture")
        self.assertNotEqual(self.package().returncode, 0)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
