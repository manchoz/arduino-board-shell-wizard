# SPDX-License-Identifier: MPL-2.0
"""Export a committed wizard revision as a portable Agent Plugins ZIP."""
import argparse
from io import BytesIO
import json
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import zipfile


ROOT = Path(__file__).resolve().parent.parent
SKILL = ".agents/skills/arduino-board-provision/"
IDENTITY = ("name", "version", "description", "author", "homepage", "repository", "license", "keywords")
REQUIRED = (
    "board-host.sh", "board-host.ps1", "board/board-common.sh", "board/board-request.sh",
    "board/setup-arduino-board.sh", "board/reset-arduino-board.sh", "host/board-ssh.sh",
    "host/board-ssh.ps1", "AGENTS.md", "README.md", "LICENSE", "docs/adb.md",
    "docs/usage.md", "docs/unattended.md", "docs/technical.md", "docs/agent-workspace.md",
    "docs/manual-transfer.md", "docs/plugin-distribution.md", "docs/privacy.md",
    ".codex-plugin/plugin.json", ".claude-plugin/plugin.json",
    ".agents/plugins/marketplace.json", ".claude-plugin/marketplace.json",
    SKILL + "SKILL.md", SKILL + "agents/openai.yaml",
)


def package(ref):
    commit = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--verify", "--end-of-options",
                             ref + "^{commit}"], check=True, capture_output=True).stdout.decode().strip()
    exported = subprocess.run(["git", "-C", str(ROOT), "-c", "core.autocrlf=false", "archive",
                               "--format=zip", commit], check=True, capture_output=True).stdout
    result = BytesIO()
    with zipfile.ZipFile(BytesIO(exported)) as source:
        names = source.namelist()
        if any(name.split("/", 1)[0].casefold() in ("plugin.json", "skills") for name in names):
            raise ValueError("Committed plugin.json or skills/ conflicts with generated portable members")
        for name in REQUIRED:
            if name not in names:
                raise ValueError("Missing committed file: " + name)
        for info in source.infolist():
            path = PurePosixPath(info.filename)
            if path.is_absolute() or ".." in path.parts or stat.S_ISLNK(info.external_attr >> 16):
                raise ValueError("Unsafe package member: " + info.filename)
            if info.filename.endswith(".sh") and b"\r" in source.read(info):
                raise ValueError("Bash file must use LF: " + info.filename)
        native = json.loads(source.read(".codex-plugin/plugin.json"))
        claude = json.loads(source.read(".claude-plugin/plugin.json"))
        plugin_name = native.get("name")
        if not isinstance(plugin_name, str) or len(plugin_name) > 64 or not re.fullmatch(
                r"(?!.*(?:--|\.\.))[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", plugin_name):
            raise ValueError("Plugin name must match the Agent Plugins 1.0.0 schema")
        for key in IDENTITY:
            if native.get(key) != claude.get(key):
                raise ValueError("Plugin manifests disagree on " + key)
        if native.get("skills") != "./.agents/skills/" or claude.get("skills") != native["skills"]:
            raise ValueError("Native manifests must discover the maintained skill directory")
        if native.get("requires_local_executor") is not True:
            raise ValueError("The plugin requires local execution")
        manifest = {key: native[key] for key in IDENTITY if key in native}
        manifest["$schema"] = "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"
        manifest["extensions"] = {"com.openai": {"requires_local_executor": True,
                                                "interface": native["interface"]}}
        claude["skills"] = "./skills/"
        with zipfile.ZipFile(result, "w", compression=zipfile.ZIP_DEFLATED) as target:
            for info in source.infolist():
                data = source.read(info)
                if info.filename == ".claude-plugin/plugin.json":
                    data = (json.dumps(claude, indent=2) + "\n").encode()
                target.writestr(info, data)
                if info.filename.startswith(SKILL):
                    copied = zipfile.ZipInfo(info.filename.replace(".agents/skills/", "skills/", 1), info.date_time)
                    copied.external_attr = info.external_attr
                    copied.compress_type = zipfile.ZIP_DEFLATED
                    target.writestr(copied, data)
            target.writestr("plugin.json", json.dumps(manifest, indent=2) + "\n")
    return result.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", required=True, help="Committed Git revision to export")
    parser.add_argument("--output", required=True, type=Path, help="New ZIP file; existing files are preserved")
    args = parser.parse_args()
    try:
        content = package(args.ref)
        with args.output.open("xb") as output:
            output.write(content)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print("Packaging failed: " + str(error), file=sys.stderr)
        return 1
    print("Created portable plugin ZIP")
    return 0


if __name__ == "__main__":
    sys.exit(main())
