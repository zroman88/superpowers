# How To: Install Superpowers Plugin (Local / Non-Marketplace)

This guide covers installing our **modified version** of the Superpowers AI coding agent skills plugin **locally**, bypassing the official Cursor plugin marketplace.

Superpowers is a complete software development methodology for coding agents — it provides skills for brainstorming, TDD, systematic debugging, code review, and more. Once installed, these skills auto-trigger at the right moments without any manual intervention.

---

## Why This Version (Not the Marketplace)

We are having everyone install this specific modified version of Superpowers rather than the official marketplace release for two important reasons:

### 1. Fixes for Cursor Compatibility Issues

The upstream marketplace version of Superpowers has known issues when running inside Cursor:

* **Skill loading mechanism mismatch** — The stock Superpowers tells the agent to use a "Skill tool" that doesn't exist in Cursor. Our version includes a Cursor Agent adapter that correctly routes skill loading through Cursor's `Read` tool using absolute paths from the available-skills list.
* **Subagent / Task tool problems** — Cursor's Task tool forces subagents to the `composer-2-fast` model, which produces unacceptable results. Our version includes a Task tool ban that prevents the agent from dispatching subagents, keeping all work in the main agent context where it performs reliably.
* **Hook output format** — Cursor only recognizes `additional_context` (snake_case). The upstream version can emit the wrong JSON key format, causing the bootstrap to silently fail. Our version detects Cursor sessions and outputs the correct format.

Without these fixes, Superpowers skills either don't load at all or behave unpredictably in Cursor.

### 2. Jira Ticket Integration for Analysis and Brainstorming

Our modified version integrates with the Atlassian MCP (Jira/Confluence) to enhance the brainstorming and planning workflows:

* **Read and intake Jira tickets** — The agent can pull in full ticket details including descriptions, acceptance criteria, and linked issues to use as context during brainstorming and spec writing.
* **Analyze ticket comments** — All comments on a Jira ticket are ingested, giving the agent visibility into prior discussion, decisions, blockers, and context that shaped the requirements.
* **Informed brainstorming** — Instead of starting from scratch, the brainstorming skill can build on existing Jira context — understanding what's already been decided, what constraints exist, and what the team has discussed.

This means when you point the agent at a Jira ticket and say "let's work on D42-XXXXX," it can fetch the ticket, read through the comment history, and brainstorm with full project context rather than asking you to re-explain everything.

---

## Prerequisites

* **rsync** installed (pre-installed on macOS and most Linux distros)
* **Cursor IDE** and/or **Claude Code** installed on your machine
* Access to the download link below

---

## Quick Install (Automated Script)

The fastest way to install is using the included script. It detects whether you have Cursor, Claude Code, or both, and installs to the correct locations automatically.

### Step 1: Download and Extract

Download the Superpowers archive from Google Drive:

[**Download Superpowers (Google Drive)**](https://drive.google.com/file/d/1xP8OCdLaEpQxM9ithmZ4J-Bds58jp_VX/view?usp=sharing)

Extract it to your home directory:

```shell
cd ~
unzip superpowers-d42.zip -d superpowers
```

This creates `~/superpowers/` on your machine. Keep this directory — you'll use it if you need to re-install after an update.

**Important:** Do NOT install the official Superpowers from the Cursor marketplace or from the `obra/superpowers` GitHub repo. Those versions do not include our Cursor fixes or Jira integration.

### Step 2: Run the Install Script

```shell
cd ~/superpowers
./scripts/install-superpowers.sh
```

The script will:

1. Check if `~/.cursor/` exists → install the Cursor plugin
2. Check if `~/.claude/` exists → install the Claude Code plugin
3. Copy all skill files, hooks, commands, and agents to the correct plugin directories
4. Create/update the `~/.cursor/hooks.json` file so the session-start hook fires automatically
5. Print post-install instructions

---

## ⚠️ CRITICAL: Disable Third-Party Plugin Imports in Cursor

**You MUST disable the third-party plugin import settings in Cursor.** If you don't, Cursor will also load the marketplace version of Superpowers, causing duplicate and conflicting skills. This is the single most common cause of Superpowers not working correctly.

### How to disable:

1. Open **Cursor Settings** (gear icon in the bottom-left, or `Ctrl+,` / `Cmd+,`)
2. Navigate to **Rules, Skills, Subagents**
3. Find these two toggles and turn them **OFF** (they are ON by default):

    * **"Include third-party Plugins, Skills, and other configs"** — toggle this OFF
    * **"Automatically import agent configs from other tools"** — toggle this OFF

Both toggles are at the bottom of the Rules, Skills, Subagents section. They have yellow/gold toggle switches when enabled — make sure both are switched OFF (grey).

**Why this matters:** With these enabled, Cursor pulls the stock Superpowers from its own marketplace cache. Since you're installing our modified local copy with the Cursor fixes and Jira integration, you'll end up with two conflicting copies loading simultaneously — the stock version without the fixes and our version with them. The agent gets confused by duplicate, contradictory instructions and behaves unpredictably. Always disable these when using a local installation.

---

## Manual Installation (Step-by-Step)

If you prefer to install manually without the script, follow these steps.

### For Cursor

#### 1. Download and extract

Download from [**Google Drive**](https://drive.google.com/file/d/1xP8OCdLaEpQxM9ithmZ4J-Bds58jp_VX/view?usp=sharing) and extract to `~/superpowers`.

#### 2. Copy to Cursor's local plugins directory

```shell
mkdir -p ~/.cursor/plugins/local/superpowers
rsync -a ~/superpowers/skills/ ~/.cursor/plugins/local/superpowers/skills/
rsync -a ~/superpowers/hooks/ ~/.cursor/plugins/local/superpowers/hooks/
rsync -a ~/superpowers/commands/ ~/.cursor/plugins/local/superpowers/commands/
rsync -a ~/superpowers/agents/ ~/.cursor/plugins/local/superpowers/agents/
rsync -a ~/superpowers/assets/ ~/.cursor/plugins/local/superpowers/assets/
rsync -a ~/superpowers/.cursor-plugin/ ~/.cursor/plugins/local/superpowers/.cursor-plugin/
rsync -a ~/superpowers/.claude-plugin/ ~/.cursor/plugins/local/superpowers/.claude-plugin/
cp ~/superpowers/CLAUDE.md ~/.cursor/plugins/local/superpowers/
cp ~/superpowers/README.md ~/.cursor/plugins/local/superpowers/
cp ~/superpowers/LICENSE ~/.cursor/plugins/local/superpowers/
cp ~/superpowers/package.json ~/.cursor/plugins/local/superpowers/
```

If `AGENTS.md` is a symlink to `CLAUDE.md` in the repo, recreate it:

```shell
cd ~/.cursor/plugins/local/superpowers
ln -sf CLAUDE.md AGENTS.md
```

#### 3. Make the session-start hook executable

```shell
chmod +x ~/.cursor/plugins/local/superpowers/hooks/session-start
```

#### 4. Create the Cursor hooks.json

This is the file that tells Cursor to run the Superpowers bootstrap on every new Agent session.

Create (or replace) `~/.cursor/hooks.json`:

```json
{
  "version": 1,
  "hooks": {
    "sessionStart": [
      {
        "command": "/home/YOUR_USERNAME/.cursor/plugins/local/superpowers/hooks/session-start"
      }
    ]
  }
}
```

**Replace** `/home/YOUR_USERNAME/` with your actual home directory path. You can find it with `echo $HOME`.

#### 5. Disable third-party plugin imports

Follow the steps in the **CRITICAL** section above to disable the marketplace plugin toggles.

#### 6. Restart Cursor

Close and reopen Cursor completely. The plugin loads on startup.

---

### For Claude Code

If you're using VS Code Claude IDE plugin (not CLI), add these to your `settings.json` of Cursor

```
  "claudeCode.allowDangerouslySkipPermissions": true,
  "claudeCode.initialPermissionMode": "bypassPermissions",
```

this'll let you run superpowers after planning/speccing fully automated without being prompted for an approval every minute!

# Modify your claude settings.json:

###
This is what my env json section looks like in `~/.claude/settings.json`!

```
"env": {
  4     "MAX_THINKING_TOKENS": "32000",
  5     "AWS_PROFILE": "claude-code",
  6     "ANTHROPIC_MODEL": "global.anthropic.claude-opus-4-6-v1",
  7     "ANTHROPIC_DEFAULT_OPUS_MODEL": "global.anthropic.claude-opus-4-6-v1",
  8     "ANTHROPIC_DEFAULT_MODEL": "global.anthropic.claude-opus-4-6-v1",
  9     "ANTHROPIC_DEFAULT_HAIKU_MODEL": "global.anthropic.claude-haiku-4-5-20251001-v1:0",
  10     "ANTHROPIC_DEFAULT_SONNET_MODEL": "global.anthropic.claude-sonnet-4-6",
  11     "POSTMAN_API_KEY": "<your postman api key that you've generated>",
  12     "CLAUDE_CODE_EFFORT_LEVEL": "max"
  13   }
```

**I use max effort with opus 4.6 for most planning/speccing and switch to sonnet max for implementation, but make sure you reverify and write unit tests using Opus!**

#### 1. Download and extract (if not already done)

Download from [**Google Drive**](https://drive.google.com/file/d/1xP8OCdLaEpQxM9ithmZ4J-Bds58jp_VX/view?usp=sharing) and extract to `~/superpowers`.

#### 2. Copy to Claude Code's local plugins directory

```shell
mkdir -p ~/.claude/plugins/local/superpowers
rsync -a ~/superpowers/skills/ ~/.claude/plugins/local/superpowers/skills/
rsync -a ~/superpowers/hooks/ ~/.claude/plugins/local/superpowers/hooks/
rsync -a ~/superpowers/commands/ ~/.claude/plugins/local/superpowers/commands/
rsync -a ~/superpowers/agents/ ~/.claude/plugins/local/superpowers/agents/
rsync -a ~/superpowers/.claude-plugin/ ~/.claude/plugins/local/superpowers/.claude-plugin/
cp ~/superpowers/CLAUDE.md ~/.claude/plugins/local/superpowers/
cp ~/superpowers/README.md ~/.claude/plugins/local/superpowers/
cp ~/superpowers/LICENSE ~/.claude/plugins/local/superpowers/
```

#### 3. Make the hook executable

```shell
chmod +x ~/.claude/plugins/local/superpowers/hooks/session-start
chmod +x ~/.claude/plugins/local/superpowers/hooks/run-hook.cmd
```

#### 4. Disable the marketplace version (if installed)

If you previously installed Superpowers from the Claude Code marketplace, disable it:

```shell
claude settings set enabledPlugins.superpowers@claude-plugins-official false
```

#### 5. Restart Claude Code

Start a fresh Claude Code session for the plugin to load.

---

## How the Hook Works

Superpowers uses a **session-start hook** — a shell script that runs every time you open a new Agent chat. Here's what it does:

1. The hook script lives at `plugins/local/superpowers/hooks/session-start`
2. When Cursor starts a new Agent session, it reads `~/.cursor/hooks.json` and executes the command listed under `sessionStart`
3. The script reads the `using-superpowers` skill content and outputs it as `additional_context` in JSON format
4. Cursor injects this context into the Agent's system prompt
5. The Agent now knows about all available skills and will auto-trigger them at the right moments

The hook is what makes skills **automatic** — without it, Superpowers is just files on disk. With it, the Agent reads skills before creative work, uses TDD patterns, runs brainstorming before building features, etc.

### hooks.json format for Cursor

```json
{
  "version": 1,
  "hooks": {
    "sessionStart": [
      {
        "command": "/absolute/path/to/hooks/session-start"
      }
    ]
  }
}
```

The path **must be absolute**. Relative paths will not resolve correctly.

---

## Verifying the Installation

After installing and restarting:

1. Open a **new** Agent chat in Cursor
2. Send exactly this message: `Let's make a react todo list`
3. **Expected behavior:** The Agent auto-triggers the `brainstorming` skill before writing any code. It will ask you clarifying questions about your requirements, explore design options, and present a structured specification before implementation.
4. **If it just starts writing code immediately**, the hook is not working. Check:

    * Does `~/.cursor/hooks.json` exist and contain the correct absolute path?
    * Is the `session-start` script executable? (`chmod +x`)
    * Did you restart Cursor after installation?
    * Are the third-party plugin toggles disabled?

### Testing Jira Integration

To verify the Jira ticket integration works:

1. Open a new Agent chat
2. Mention a Jira ticket: `Let's brainstorm on PROJ-123` (use a real ticket key)
3. **Expected behavior:** The Agent should read the brainstorming skill, then fetch the Jira ticket and its comments via the Atlassian MCP before beginning the brainstorming workflow. It will incorporate the ticket's context, prior discussions, and requirements into the design exploration.

---

## Updating

When a new version is distributed, download the updated archive from Google Drive, extract it over your existing `~/superpowers` directory, and re-run the install script:

```shell
cd ~/superpowers
./scripts/install-superpowers.sh
```

Then restart Cursor/Claude Code.

---

## Uninstalling

To remove Superpowers completely:

```shell
cd ~/superpowers
./scripts/install-superpowers.sh --uninstall
```

Or manually:

```shell
rm -rf ~/.cursor/plugins/local/superpowers
rm -f ~/.cursor/hooks.json
rm -rf ~/.claude/plugins/local/superpowers
```

Then restart Cursor/Claude Code.

---

## Troubleshooting

| Problem | Solution |
| --- | --- |
| Skills don't auto-trigger | Check `~/.cursor/hooks.json` path is absolute and correct |
| Duplicate skills appearing | Disable third-party plugin imports (see CRITICAL section) |
| `session-start` permission denied | Run `chmod +x ~/.cursor/plugins/local/superpowers/hooks/session-start` |
| Hook runs but Agent ignores skills | Restart Cursor completely (not just the chat) |
| `rsync: command not found` | Install rsync: `sudo apt install rsync` (Linux) or `brew install rsync` (macOS) |
| Claude Code doesn't pick up plugin | Make sure `.claude-plugin/plugin.json` is present in the install directory |
| Agent uses Task tool / subagents | The Cursor fix should ban this automatically; verify you're running our version, not marketplace |
| Jira tickets not fetched during brainstorming | Ensure the Atlassian MCP server is configured and authenticated in Cursor settings |

---

## What's Included

The Superpowers plugin provides these auto-triggering skills:

* **brainstorming** — Socratic design exploration before implementation (with Jira ticket intake)
* **test-driven-development** — RED-GREEN-REFACTOR enforcement
* **systematic-debugging** — 4-phase root cause analysis
* **writing-plans** — Detailed implementation planning
* **executing-plans** — Batch execution with review checkpoints
* **subagent-driven-development** — Parallel agent task execution
* **requesting-code-review** / **receiving-code-review** — Structured review workflows
* **using-git-worktrees** — Isolated development branches
* **verification-before-completion** — Evidence-based completion claims
* **writing-skills** — Meta-skill for creating new skills

---

_Last updated: May 8, 2026_
