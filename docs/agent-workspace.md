# Prepare your project's boards with an agent

Use this walkthrough when you are developing an Uno Q project with an agent and want to prepare several boards as deployment targets. It also applies to Ventuno Q boards running the official Linux image. Enable the workspace once, then ask the agent to provision each board through `board-host`.

A project skill can use a separate local wizard installation, as in steps 2–4. Codex and Claude Code also support the [bundled plugin alternative](#alternative-install-the-bundled-plugin), which installs the instructions, scripts, and guides together. During provisioning the agent reads local files and invokes the host launcher; it does not download scripts automatically. This workflow prepares board settings and access; deploy your application afterward using your project's deployment workflow.

## 1. Prepare the host

Run the agent on the computer connected to the boards, with permission to execute local commands. Remote, container, and cloud agents need an existing connection to that computer's USB/ADB devices; installing a skill does not provide one.

Follow the [ADB setup guide](adb.md). App Lab or the Arduino Q Boards core in the Arduino IDE may already supply ADB, so check those installations before installing another copy. Make ADB available in the environment where the **agent** executes commands. Changing `PATH` in a separate terminal does not change an already-running agent's environment; start the agent from the configured terminal or use your agent's environment settings.

Windows launchers need PowerShell 5.1 or 7; Linux/macOS launchers use Bash, including macOS's supplied Bash 3.2. Optional SSH integration also needs the [OpenSSH client](adb.md#optional-openssh-client).

## 2. Install the wizard locally

Keep a complete [wizard checkout](https://github.com/manchoz/arduino-board-shell-wizard) outside the application repository, so it can serve several projects. With Git installed, open a terminal at your **application project's root** and run the matching block. These variables are also used in step 3.

Windows PowerShell:

```powershell
$projectRoot = (Get-Location).Path
$toolRoot = Join-Path $env:LOCALAPPDATA 'ArduinoBoardWizard\tool'
git clone https://github.com/manchoz/arduino-board-shell-wizard.git $toolRoot
```

Linux/macOS Bash:

```sh
project_root="$PWD"
tool_root="$HOME/.local/share/arduino-board-shell-wizard"
git clone https://github.com/manchoz/arduino-board-shell-wizard.git "$tool_root"
```

If the wizard is already installed, skip cloning and set `$toolRoot` or `$tool_root` to its absolute directory. If you prefer a ZIP, extract the complete [main branch archive](https://github.com/manchoz/arduino-board-shell-wizard/archive/refs/heads/main.zip) and set the same variable to its extracted root. When using the ZIP, also set `$projectRoot` or `$project_root` to your application project's root.

The tool root must contain `board-host.ps1`, `board-host.sh`, `board/`, `host/`, `docs/`, `AGENTS.md`, and `.agents/skills/arduino-board-provision/`. Keep the complete layout. **v0.1.0 does not include the skill**; use the current checkout/main archive or a later release containing that folder.

## 3. Enable the skill in your project

The [portable skill](../.agents/skills/arduino-board-provision/SKILL.md) follows the [Agent Skills standard](https://agentskills.io). Copy its entire `arduino-board-provision` folder from the tool into your agent's project skill directory, including `SKILL.md` and `agents/openai.yaml`. The YAML supplies optional Codex display metadata; the workflow itself is agent-neutral.

| Agent | Project skill directory | Official guide |
| --- | --- | --- |
| Codex | `.agents/skills` | [Discovery and invocation](https://developers.openai.com/codex/skills) |
| Claude Code | `.claude/skills` | [Discovery and invocation](https://code.claude.com/docs/en/skills) |
| Other compatible agents | The host's documented project skill directory | Follow that host's Agent Skills instructions. |

Continue in the **same terminal**, with the tool and project variables from step 2. Replace `<PROJECT_SKILL_DIRECTORY>` with the directory from the table before running the matching block. If that directory already contains `arduino-board-provision`, inspect and compare the existing skill before replacing it.

Windows PowerShell:

```powershell
$skillParent = Join-Path $projectRoot '<PROJECT_SKILL_DIRECTORY>'
New-Item -ItemType Directory -Path $skillParent -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $toolRoot '.agents/skills/arduino-board-provision') -Destination $skillParent -Recurse
```

Linux/macOS Bash:

```sh
skill_parent="$project_root/<PROJECT_SKILL_DIRECTORY>"
mkdir -p "$skill_parent"
cp -R "$tool_root/.agents/skills/arduino-board-provision" "$skill_parent/"
```

Open the application project in your agent and confirm that it discovers `arduino-board-provision`. Follow the host's reload instructions or restart the agent if it does not appear. Codex also discovers the source skill directly when you work in the wizard repository itself.

For use across all your projects, copy the same folder into the host's personal skill directory instead: `~/.agents/skills/` for Codex or `~/.claude/skills/` for Claude Code. On Windows, `~` is your user-profile directory. Choose project or personal installation to avoid duplicate skill entries. Recopying the skill and updating the wizard are separate operations; keep them from the same revision when updating.

## Alternative: install the bundled plugin

This alternative replaces steps 2–4 for Codex and Claude Code. Complete the host preparation in step 1 first. The plugin includes the wizard and resolves its installed tool root automatically, so a separate tool-root instruction is unnecessary. Keep private requests outside the plugin cache as well as the application repository.

**Availability:** these commands require a published repository revision containing the plugin manifests/catalogs (plugin version `0.3.0` or later). The existing `v0.2.0` release supplies the standalone skill only. See [packaging and publication](plugin-distribution.md) for the portable ZIP and directory requirements.

Run the matching commands from your **application workspace**. GitHub installation downloads the full plugin at installation time; subsequent provisioning uses its cached local scripts.

Codex CLI, with plugin support:

```sh
codex plugin marketplace add manchoz/arduino-board-shell-wizard
codex plugin add arduino-board-shell-wizard@manchoz-arduino
```

Claude Code, using project installation:

```sh
claude plugin marketplace add manchoz/arduino-board-shell-wizard
claude plugin install arduino-board-shell-wizard@manchoz-arduino --scope project
```

Start a new agent session after installation. Use the natural-language prompts below, or explicitly invoke `$arduino-board-shell-wizard:arduino-board-provision` in Codex and `/arduino-board-shell-wizard:arduino-board-provision` in Claude Code. Avoid enabling a copied standalone version of the same skill alongside the plugin. Codex installation settings are managed by its client; use the standalone project installation above when you need project-local skill files.

Continue at step 5 and omit the `Arduino Shell Wizard tool root` line from plugin prompts. The agent should report the bundled revision and locate the tools from the installed skill path. An explicitly requested external installation takes precedence; remove an obsolete personal tool-root instruction if you intend to use the bundle instead.

### Test a local bundle without hardware

You can test local installation before publishing to GitHub. Use a clean native export containing the plugin files or an extracted portable ZIP. A preview ZIP supplied by your agent also works before the implementation is committed. The [local validation guide](plugin-distribution.md#test-the-current-checkout) covers checkout checks and the committed-revision requirement for building your own ZIP.

On Windows, open a **new PowerShell terminal at the exported or extracted plugin root**. Keep the disposable agent profiles outside that root, so installation cannot copy profile data into the bundle. These commands use temporary profiles rather than your normal agent configuration.

Codex:

```powershell
$codexTestHome = Join-Path ([IO.Path]::GetTempPath()) ('codex-wizard-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $codexTestHome | Out-Null
$env:CODEX_HOME = $codexTestHome
codex plugin marketplace add .
codex plugin add arduino-board-shell-wizard@manchoz-arduino
codex plugin list
```

After installation, change to a separate application workspace and start `codex` in the **same terminal**. A fresh profile may require `codex login` first. Before signing in, protect the test-profile directory using the [Windows private-directory ACL pattern](unattended.md#windows-storage-and-launcher); apply it to `$codexTestHome` instead of the request directory. Keep sign-in credentials out of chat.

Claude Code:

```powershell
$claudeTestHome = Join-Path ([IO.Path]::GetTempPath()) ('claude-wizard-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $claudeTestHome | Out-Null
$env:CLAUDE_CONFIG_DIR = $claudeTestHome
claude --plugin-dir .
```

This loads the local folder directly. For a test from another application workspace, pass the exported plugin root's absolute path to `--plugin-dir` instead of `.`. If the client requests sign-in, protect `$claudeTestHome` with the same private-directory pattern first and follow its sign-in instructions.

In the test session, send this prompt. For Claude Code, replace the first line with `Use /arduino-board-shell-wizard:arduino-board-provision.`:

```text
Use $arduino-board-shell-wizard:arduino-board-provision.
Check provisioning readiness without hardware.
Resolve the bundled tool root and read its agent and unattended guides.
Confirm the launchers, board scripts, host helpers, and guides are present.
Locate ADB and check its version only.
Do not list devices, contact a board, launch setup, or change SSH config.
Report missing requirements.
```

Expect the agent to locate the installed bundle and report available or missing host requirements without asking for a separately installed wizard. This checks discovery and workspace readiness; it does not verify board configuration or Wi-Fi/SSH reachability. An agent already working in this wizard repository can also use its discovered skill with this prompt, but that alone does not test installation into a different workspace.

Close the test terminal when finished; the environment overrides apply only to that terminal and its child processes. Remove only the disposable profile/export directories you created when you no longer need them, including any test-profile sign-in data. Do not put `CODEX_HOME` or `CLAUDE_CONFIG_DIR` test overrides in persistent user environment settings.

## 4. Record how your agent finds the tool

Merge this snippet into your project's agent instructions, such as `AGENTS.md`, `CLAUDE.md`, or the equivalent supported by your host. Preserve the project's existing instructions.

```text
Use the arduino-board-provision skill to prepare this project's Uno Q boards.
Resolve the Arduino Shell Wizard tool root from personal instructions or the user's prompt.
Read AGENTS.md and docs/unattended.md from that tool root before provisioning.
Use explicit board serials and protected request files outside the project.
Preserve unspecified settings and stop on failure to inspect the resulting state.
```

To avoid repeating the installation path, add `Arduino Shell Wizard tool root: <absolute local installation path>` to a supported personal instruction file. There is no universal filename for local agent instructions:

| Agent | Personal instruction file | Applies to |
| --- | --- | --- |
| Codex | `~/.codex/AGENTS.md` by default | All projects for that Codex profile. |
| Claude Code | `CLAUDE.local.md` at your application project's root | That project; add the filename to your Git ignore rules. |
| Other agents | The host's documented personal/local instruction file | Follow that host's discovery rules. |

On Windows, `~` is your user-profile directory, so Codex's default file is `%USERPROFILE%\.codex\AGENTS.md`. If you set `CODEX_HOME`, use that directory instead. An existing `AGENTS.override.md` takes precedence over `AGENTS.md` in the same directory; merge the tool-root line into the active personal file. A project-root override also replaces that project's `AGENTS.md`, so it is unsuitable for adding only this path while retaining the shared instructions. See the [Codex instruction guide](https://developers.openai.com/codex/guides/agents-md) and [Claude Code instruction guide](https://code.claude.com/docs/en/memory).

Preserve existing instruction content and keep machine-specific paths out of shared project instructions. If you prefer not to store the path, supply it in each provisioning prompt. The skill resolves its guides and launchers from that tool root, even when the application workspace and copied skill are elsewhere. Installing a skill globally does not record this location.

## 5. Check workspace readiness without hardware

Ask the agent from your **application workspace**, replacing the tool-root placeholder with its absolute path for standalone installation. Plugin users omit that line and ask the agent to resolve its bundled tool root:

```text
Use the arduino-board-provision skill to check this project's provisioning readiness.
Arduino Shell Wizard tool root: <absolute local installation path>
Confirm the skill is available and read the wizard's local agent and unattended guides.
Check that its launchers, board files, host helpers, and guides are present.
Locate ADB and check adb version in the environment you will use for provisioning.
Do not list devices, contact a board, launch setup, or change SSH config.
Report any missing requirements.
```

This checks workspace configuration. It does not establish that any board is connected or ready. If scripts are missing, provide a complete local installation before proceeding.

## 6. Prepare one private request per board

Follow [Prepare and use a private request file](unattended.md#prepare-and-use-a-private-request-file) for the complete templates and private-storage commands. Create one request per board, with a unique hostname such as `project-q-01` or `project-q-02`. Store the requests outside **both** the application and wizard repositories, restrict access before writing credentials, and save as UTF-8 without a BOM. Pass only file paths to the agent; keep passwords out of chat.

For a fresh board, choose a new Linux-password source and explicitly approve enabling Network Mode. For an already provisioned board, preserve its Linux password and other settings unless you want to change them. Enabling disabled Network Mode while keeping its password requires the current Linux password for authentication. Linux and Wi-Fi passwords are separate; the [request contract](unattended.md#request-contract) owns their validation rules.

If deployment uses SSH, explicitly select an existing **public** key and provide its path with the provisioning prompt. Ask the agent to install it and, if needed, supply the board's reachable address. Network Mode must be enabled. This updates the host SSH config and restricts its SSH directory to your account; read [SSH integration details](technical.md#ssh-client-integration) first. The skill does not generate keys implicitly, and key installation over ADB does not verify network reachability.

## 7. Ask the agent to provision your boards

Connect the boards over USB and identify their serials with `adb devices -l`, using entries listed as `device`. If several devices are hard to match to physical boards, connect one board at a time while recording its serial. The agent also checks that each selected device is a supported board before configuration.

Prepare a nonsecret inventory for your local prompt:

| Serial | Requested hostname | Private request file |
| --- | --- | --- |
| `SERIAL_01` | `project-q-01` | `<full private request path for board 01>` |
| `SERIAL_02` | `project-q-02` | `<full private request path for board 02>` |

Replace serials and file-path placeholders with the actual values, and make each request's hostname match the inventory. Keep concrete private storage paths in your local prompt rather than committing this inventory. There is no batch request format: the agent invokes the existing launcher once per board.

Use this prompt in the application workspace:

```text
Use arduino-board-provision.
Arduino Shell Wizard tool root: <absolute local installation path>
Provision these Uno Q deployment targets:
- Serial SERIAL_01, hostname project-q-01, request <full private request path for board 01>.
- Serial SERIAL_02, hostname project-q-02, request <full private request path for board 02>.
Apply the explicit Wi-Fi, Linux-password, and Network Mode choices in each private request.
Inspect each board before changing it and pass its explicit serial to the launcher and subsequent ADB commands.
Process the boards one at a time, verifying each before moving to the next.
Stop on any failure, inspect that board's state, and report the remaining boards as pending.
Do not retry configuration automatically or print request contents or passwords.
Report the tool revision/hash, each board's result, and the checks actually performed.
```

For standalone skills, Codex supports explicit `$arduino-board-provision` invocation and Claude Code uses `/arduino-board-provision`. Plugin installation uses `$arduino-board-shell-wizard:arduino-board-provision` in Codex and `/arduino-board-shell-wizard:arduino-board-provision` in Claude Code. Plugin users omit the tool-root line in the prompt. Other hosts use their documented invocation mechanism. If the agent cannot match a board or needs a missing credential or setup choice, resolve that before configuration. If a private request conflicts with your prompt, resolve the conflict first.

The agent runs the matching [host launcher command](unattended.md#prepare-and-use-a-private-request-file) from the **wizard tool root**, using the selected serial and private request-file path. The launcher transfers and verifies the board scripts, sends the request through stdin, and cleans up uploaded scripts afterward.

## 8. Review each deployment target

For each board, ask for the result's `status`, `stage`, `completed`, and `skipped`, any cleanup warning, and the actual hostname, requested Wi-Fi connection, and Network Mode state. Password changes also need the checks in [Check setup results](usage.md#check-setup-results). Keep credentials in protected storage for future login.

When your project needs network access, request a separate connectivity check from the deployment computer. If you requested SSH integration, verify external SSH/Bonjour as applicable. Wi-Fi, Network Mode, and an SSH key are distinct parts of readiness; USB/ADB access or a loopback SSH test alone does not establish that another computer can reach the board.

If a board fails or loses USB, retain the protected request and access to its credentials. Earlier changes may remain even without a JSON result. Inspect actual state and decide how to resume before retrying; at stage `ssh`, board setup has already finished. See [Results and failure handling](unattended.md#results-and-failure-handling).

Once the requested provisioning and connectivity checks succeed, use your project's deployment workflow to install or run the application. This provisioning skill supports setup and Wi-Fi updates, with optional SSH integration; resets, flashing, and application deployment are separate operations.

Return to the [quick start](../README.md) or the [unattended request guide](unattended.md).
