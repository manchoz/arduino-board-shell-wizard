# Plugin packaging and publication

For installation and provisioning prompts, use the [workspace guide](agent-workspace.md#alternative-install-the-bundled-plugin). The plugin supplies local tools and instructions for setup on the official Uno Q / Ventuno Q Linux image. Host requirements remain in the [ADB guide](adb.md); credentials and results follow the existing [unattended contract](unattended.md).

## Package layout

The GitHub repository is the native plugin root. `.codex-plugin/plugin.json` and `.claude-plugin/plugin.json` discover the maintained `.agents/skills/` directory. Each agent has a marketplace catalog named `manchoz-arduino`, with the single `arduino-board-shell-wizard` entry pointing to `./`. Both manifests use version `0.3.0` and the same publisher and MPL-2.0 metadata.

The portable ZIP adds root `plugin.json` using the [Agent Plugins schema](https://agent-plugins.org/schemas/1.0.0/plugin.schema.json). Its OpenAI extension declares `requires_local_executor: true`. A generated copy of the maintained skill lives under `skills/`; Claude's packaged manifest scans that directory only. The original skill remains in the ZIP so existing documentation links and standalone installation examples work. Maintain the source skill once, rather than editing generated copies.

All launchers, board payloads, host helpers, and guides travel together. The skill finds the bundled tool root from its installed source path; copied standalone skills still use the separately supplied tool root. Provisioning calls the existing host launcher once per selected board. There is no MCP server or installation hook.

## Build a portable ZIP

Use Python 3.10 or later and Git. Run from a complete repository checkout containing the packager. Choose a **committed revision containing the plugin files**; earlier releases such as `v0.2.0` cannot produce this bundle. The packager exports that revision, excluding untracked files and later working-tree edits. It validates required files, matching manifests, the portable schema's plugin-name rules, LF Bash files, and member paths before creating a new output file. Committed root `plugin.json` or `skills/` entries are rejected regardless of case, preventing collisions with generated portable files on Windows. Existing output files are preserved.

Windows PowerShell:

```powershell
$pluginRef = 'HEAD'
$pluginZip = Join-Path ([IO.Path]::GetTempPath()) ('arduino-board-shell-wizard-' + [guid]::NewGuid().ToString('N') + '.zip')
python .\scripts\package-plugin.py --ref $pluginRef --output $pluginZip
```

Linux/macOS Bash:

```sh
plugin_ref=HEAD
plugin_dir=$(mktemp -d)
plugin_zip="$plugin_dir/arduino-board-shell-wizard.zip"
python3 scripts/package-plugin.py --ref "$plugin_ref" --output "$plugin_zip"
```

Keep the generated ZIP outside the source checkout and review its contents before distribution. Its root contains the manifests and launchers directly, without an enclosing repository directory. Packaging does not install ADB, configure a board, or establish network reachability.

## Hardware-free validation

Run `python tests/test-plugin-package.py` from the repository root. Its disposable Git fixtures check committed bytes, skill copies, native/portable metadata, missing/invalid plugin names and valid length boundaries, case-variant generated-path collisions, LF endings, excluded untracked files, missing files, invalid revisions, symlink rejection, and preservation of existing output on failure. Run the remaining [hardware-free checks](technical.md#hardware-free-checks) when changing scripts or source notices.

### Test the current checkout

You can run the package regressions and validate the native manifests before committing or publishing. From the **repository root**, in Windows PowerShell:

```powershell
python .\tests\test-plugin-package.py
claude plugin validate . --json
claude plugin validate .claude-plugin/marketplace.json --json
```

The Python tests create their own disposable committed repositories. Claude validation checks the current checkout; it does not provision a board or establish a Codex installation in another workspace.

For an interactive Codex or Claude test, follow [Test a local bundle without hardware](agent-workspace.md#test-a-local-bundle-without-hardware). That walkthrough uses a clean export or extracted ZIP, disposable agent profiles, the correct namespaced invocation, and a readiness prompt that forbids board contact. Do not register a working-tree copy containing private local files as an installation source.

The ZIP builder exports committed revisions only. While plugin changes are uncommitted, `--ref HEAD` still refers to the earlier implementation and will fail if it lacks the required plugin files. Use an agent-provided preview ZIP for local installation, or commit the implementation before [building a ZIP](#build-a-portable-zip). Publishing to GitHub is unnecessary for local tests.

### Validate an exported bundle

For plugin validation, export a clean source revision or extract the portable ZIP into disposable storage. From that exported root:

```sh
claude plugin validate . --json
claude plugin validate .claude-plugin/marketplace.json --json
```

For installation tests, use the [disposable-profile walkthrough](agent-workspace.md#test-a-local-bundle-without-hardware) and a separate application workspace. Register and install each layout, inspect the cached files, and run the [readiness prompt](agent-workspace.md#5-check-workspace-readiness-without-hardware). Test both bundled discovery and a copied skill resolving a separate tool installation. Keep credentials, requests, keys, and SSH config outside these packages; use mocks for provisioning tests.

## Public-directory preparation

GitHub marketplace installation is separate from [OpenAI directory submission](https://developers.openai.com/plugins/deploy/submission). Submit the portable ZIP through the skills-only path and follow the [desktop-only requirements](https://developers.openai.com/plugins/deploy/desktop-only). This tool runs local programs, so public distribution requires a local executor. Native CLI availability and directory installation surfaces can differ.

Package metadata identifies the GitHub publisher as `manchoz`; that does not establish verified OpenAI publishing identity. Before submission:

- Verify the submitting organization/developer identity and submission access. Confirm that the publisher matches the public package metadata.
- Publish the source and check that the declared [privacy notice](privacy.md), [license terms](../LICENSE), and repository/support links are publicly accessible. Repository issues are the support channel; keep passwords and private requests out of issues.
- Check current portal requirements for listing artwork, translations, onboarding, test evidence, and review information. Supply actual reviewed materials rather than placeholders or invented results.
- Test a clean installed-plugin workflow and provide any required walkthrough. The existing README demo is hardware-free; label it accordingly.
- Upload for automated checks, resolve findings, and obtain review approval before publication. Update package/skill versions together for subsequent ZIP submissions.

The following are **proposed review cases**, not evidence of completed plugin-driven hardware runs. Use disposable fixtures for mocked checks and obtain authorization before real-board testing.

| Positive scenario | Prompt outline | Expected behavior |
| --- | --- | --- |
| Workspace readiness | Check provisioning readiness without contacting hardware. | Resolve bundled scripts/guides, check host requirements, and make no board contact. |
| Preserve an existing setup | Provision the selected board using a protected request that keeps existing settings. | Inspect first, use the explicit serial and literal request, then compare results with state. |
| First-use setup | Prepare the selected fresh board using the supplied protected request and Network Mode approval. | Resolve required Linux credentials privately, invoke setup once, and verify requested postconditions. |
| Wi-Fi update | Connect the selected provisioned board to the requested network using its private request. | Preserve unspecified settings, distinguish Wi-Fi/Linux credentials, and verify the requested connection. |
| Optional SSH access | Set up the selected existing public key after provisioning. | Use only the selected public key, preserve SSH restrictions, and distinguish key installation from external reachability. |

| Negative scenario | Expected behavior |
| --- | --- |
| Ambiguous boards or missing private credential source | Resolve the missing information before configuration; do not guess a device or ask for passwords in chat. |
| Reset, flashing, or application deployment requested through this setup skill | Explain its setup scope and require the separate authorized workflow. |
| Partial failure or lost result | Retain USB access and protected requests, inspect actual state, and report pending boards without automatic retries. |

## License

The source is distributed under [MPL-2.0](../LICENSE). When distributing modified covered source files, preserve the applicable notices and meet the license's source-availability requirements. Projects provisioned with this tool can retain their own licenses. See the [Mozilla FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/) for the file-level scope.
