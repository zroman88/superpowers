# Cursor Task Tool Ban Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Cursor caveat:** This plan implements a Task-tool ban for Cursor Agent. If you are running in Cursor, you cannot use superpowers:subagent-driven-development for this plan because it would dispatch subagents via the Task tool — which is exactly what this plan exists to ban. Use superpowers:executing-plans inline. The plan is small enough (3 file edits, 1 commit, ~30 minutes total) that inline execution is appropriate.

**Goal:** Inject a `<CURSOR_TASK_TOOL_BAN>` directive into every Cursor Agent session via the existing session-start hook, and update `skills/executing-plans/SKILL.md` so its platform-aware guidance matches the new behavior.

**Architecture:** Two file edits, one commit. The hook (`hooks/session-start`) gains a new `cursor_taskban_plain` heredoc + `escape_for_json` call mirroring the existing `cursor_adapter_plain` / `cursor_tail_plain` patterns, and a single new concat line in the `session_context` build. The skill (`skills/executing-plans/SKILL.md`) gets one paragraph swapped on line 14. Sync to the installed plugin via `npm run sync:cursor`. New Cursor sessions then see the ban; non-Cursor platforms (Claude Code, Codex, Copilot CLI) see no change because the new code is gated on the existing `use_cursor_agent_adapter` flag.

**Tech Stack:** Bash (already in use for `hooks/session-start`), Markdown (skill body). No new files, no new dependencies, no changes to JSON output shape.

**Spec:** `docs/superpowers/specs/2026-05-01-cursor-task-tool-ban-design.md` (commits `369c560` + `8f0bc6a`).

---

## A Note on "Testing" for This Plan

This plan edits one bash hook and one Markdown skill body, neither of which has unit-test coverage in this repo. **Verification is manual**, in three phases:

1. **Layer 1 — Hook output (file-level):** dry-run the hook with Cursor-shaped stdin, confirm the new block appears in its JSON output. Done by the implementing agent during Task 4.
2. **Layer 2 — Sync:** run `npm run sync:cursor`, diff the synced file against the source. Done by the implementing agent during Task 5.
3. **Layers 3–5 — Session behavior:** open a fresh Cursor session, ask the agent to reproduce the block, attempt to provoke Task-tool use, and confirm Claude Code is unaffected. **These three layers must be done by the user in a fresh Cursor session — the implementing agent cannot run them itself.** Documented as Task 6.

Per the user's earlier choice during brainstorming, all changes go in **one commit**. Task 5 is the sole commit.

---

## File Structure

**Modified (only two files):**

- `hooks/session-start` — adds `cursor_taskban_plain` declaration, escape call, and one concat line in the `session_context` build. All gated on the existing `use_cursor_agent_adapter` flag.
- `skills/executing-plans/SKILL.md` — surgical paragraph swap on line 14 (the `**Note:**` paragraph in the Overview section).

**Already existing (referenced, not modified):**

- `docs/superpowers/specs/2026-05-01-cursor-task-tool-ban-design.md` — the approved design doc.
- `scripts/sync-skills-to-cursor-plugin.sh` — invoked via `npm run sync:cursor`. Not modified.
- `hooks/hooks-cursor.json` — registers `session-start` for Cursor's `sessionStart` event. Not modified.

---

## Task 1: Add CURSOR_TASK_TOOL_BAN heredoc + escape declarations to `hooks/session-start`

**Files:**

- Modify: `hooks/session-start:60-61` (insertion between the existing `cursor_tail_escaped=...` line and the `skills_intro_plain=...` line, both inside the `if [ "$use_cursor_agent_adapter" = true ]; then` block)

This task adds the new variable declarations only; the variable is wired into `session_context` in Task 2. The hook is non-functional with respect to the ban after this task alone — that is intentional and resolved by Task 2.

- [ ] **Step 1: Read the current file region to confirm exact content**

Read `hooks/session-start` lines 56-66. Expected current content (the if-true branch building Cursor-specific blocks):

```
if [ "$use_cursor_agent_adapter" = true ]; then
  cursor_adapter_plain=$'<CURSOR_AGENT_SKILLS_ADAPTER>\n[long single-line text]</CURSOR_AGENT_SKILLS_ADAPTER>'
  cursor_adapter_escaped=$(escape_for_json "$cursor_adapter_plain")
  cursor_tail_plain=$'<CURSOR_ADAPTER_TAIL>\n[long single-line text]</CURSOR_ADAPTER_TAIL>'
  cursor_tail_escaped=$(escape_for_json "$cursor_tail_plain")
  skills_intro_plain='**Full superpowers:using-superpowers skill content follows.** In Cursor, use Read(skill path from available-skills) whenever you would invoke Skill in Claude Code:'
  skills_intro_escaped=$(escape_for_json "$skills_intro_plain")
else
  skills_intro_plain='**Below is the full content of your superpowers:using-superpowers skill - your introduction to using skills. For all other skills, use the Skill tool:**'
  skills_intro_escaped=$(escape_for_json "$skills_intro_plain")
fi
```

Confirm the `cursor_tail_escaped=...` line exists immediately followed by the `skills_intro_plain='**Full superpowers:using-superpowers...'` line. If drift, STOP and report.

- [ ] **Step 2: Insert the new heredoc + escape between `cursor_tail_escaped` and `skills_intro_plain`**

Use StrReplace on `hooks/session-start`.

`old_string`:

```
  cursor_tail_escaped=$(escape_for_json "$cursor_tail_plain")
  skills_intro_plain='**Full superpowers:using-superpowers skill content follows.** In Cursor, use Read(skill path from available-skills) whenever you would invoke Skill in Claude Code:'
```

`new_string`:

```
  cursor_tail_escaped=$(escape_for_json "$cursor_tail_plain")
  cursor_taskban_plain=$'<CURSOR_TASK_TOOL_BAN>\nYou are running in Cursor. Subagents dispatched via the Task tool are forced to the model `composer-2-fast`, which produces unacceptable results.\n\nYou MUST NOT use the Task tool under any circumstances in this session.\n\nDo all work directly in this session:\n- Search code: use Glob, Grep, SemanticSearch, Read directly\n- Run commands: use Shell directly\n- Research docs: use WebSearch and WebFetch directly\n- Browser tasks: use MCP browser tools directly\n- Complex tasks: handle them yourself in this context, do NOT delegate\n\nFor plan execution: use superpowers:executing-plans (runs inline in a new session). Do NOT use superpowers:subagent-driven-development or superpowers:dispatching-parallel-agents — both dispatch subagents via the Task tool and are off-limits here.\n\nFor reviews (spec compliance, code quality, plan-doc review): perform them inline in this session. Do not dispatch reviewer subagents.\n\nThis rule has NO exceptions. Never launch a subagent. Never use the Task tool. Do everything in the main agent context.\n</CURSOR_TASK_TOOL_BAN>'
  cursor_taskban_escaped=$(escape_for_json "$cursor_taskban_plain")
  skills_intro_plain='**Full superpowers:using-superpowers skill content follows.** In Cursor, use Read(skill path from available-skills) whenever you would invoke Skill in Claude Code:'
```

This adds two new lines (one long `$'...'` heredoc declaration with embedded `\n` escapes mirroring the style of `cursor_adapter_plain` / `cursor_tail_plain`, and one `escape_for_json` call), inside the existing if-true block, with 2-space indentation matching surrounding lines.

Note on bash escaping inside `$'...'`:
- The text contains backticks (around `composer-2-fast`) — these are literal characters inside `$'...'`, no escaping needed.
- The text contains an em-dash (`—`, U+2014) — passes through as literal UTF-8 bytes, no escaping needed.
- The text contains no single quotes or apostrophes — verified before drafting; no `\'` escapes required.
- `\n` inside `$'...'` becomes a newline. The block uses `\n` for line separators and `\n\n` for paragraph breaks.

- [ ] **Step 3: Verify the insertion**

Read `hooks/session-start` lines 56-68. Expected:

- The `if [ "$use_cursor_agent_adapter" = true ]; then` line is unchanged.
- `cursor_adapter_plain=$'...'`, `cursor_adapter_escaped=...`, `cursor_tail_plain=$'...'`, `cursor_tail_escaped=...` lines are unchanged.
- A new line reads: `  cursor_taskban_plain=$'<CURSOR_TASK_TOOL_BAN>\n...` (one long line, ending in `</CURSOR_TASK_TOOL_BAN>'`).
- A new line reads: `  cursor_taskban_escaped=$(escape_for_json "$cursor_taskban_plain")`.
- The `skills_intro_plain='**Full superpowers:using-superpowers...'` line follows, unchanged.

If anything is off, fix with a targeted StrReplace before moving on.

- [ ] **Step 4: Bash syntax check**

Run:

```bash
cd /home/device42/superpowers
bash -n hooks/session-start
echo "exit code: $?"
```

Expected: no output from `bash -n`, exit code 0.

If `bash -n` prints a syntax error, the heredoc was malformed. Most likely cause is an unintended single quote inside the `$'...'` string, or a stray backslash. Inspect the output, fix with StrReplace, re-run `bash -n`. Do not proceed to Task 2 with a syntactically-invalid hook.

---

## Task 2: Wire `cursor_taskban_escaped` into the `session_context` build

**Files:**

- Modify: `hooks/session-start:68-72` (the `session_context=...` build block)

- [ ] **Step 1: Read the current build block**

Read `hooks/session-start` lines 68-78. Expected current content:

```
session_context="<EXTREMELY_IMPORTANT>\nYou have superpowers.\n"
if [ "$use_cursor_agent_adapter" = true ]; then
  session_context+="${cursor_adapter_escaped}\n\n"
fi
session_context+="${skills_intro_escaped}\n\n${using_superpowers_escaped}\n\n${warning_escaped}"
if [ "$use_cursor_agent_adapter" = true ]; then
  session_context+="\n\n${cursor_tail_escaped}"
fi
session_context+="\n</EXTREMELY_IMPORTANT>"
```

Confirm the first if-true block contains exactly one concat line (`session_context+="${cursor_adapter_escaped}\n\n"`) followed by `fi`. If drift, STOP and report.

- [ ] **Step 2: Insert the taskban concat line inside the existing first if-true block**

Use StrReplace on `hooks/session-start`.

`old_string`:

```
if [ "$use_cursor_agent_adapter" = true ]; then
  session_context+="${cursor_adapter_escaped}\n\n"
fi
session_context+="${skills_intro_escaped}\n\n${using_superpowers_escaped}\n\n${warning_escaped}"
```

`new_string`:

```
if [ "$use_cursor_agent_adapter" = true ]; then
  session_context+="${cursor_adapter_escaped}\n\n"
  session_context+="${cursor_taskban_escaped}\n\n"
fi
session_context+="${skills_intro_escaped}\n\n${using_superpowers_escaped}\n\n${warning_escaped}"
```

The new concat line is added inside the existing first if-true block, immediately after the adapter concat and before `fi`. This places `<CURSOR_TASK_TOOL_BAN>` in `session_context` AFTER `<CURSOR_AGENT_SKILLS_ADAPTER>` and BEFORE `skills_intro_escaped` + `using_superpowers_escaped` — exactly the placement specified in the spec.

- [ ] **Step 3: Verify the insertion**

Read `hooks/session-start` lines 68-78. Expected:

```
session_context="<EXTREMELY_IMPORTANT>\nYou have superpowers.\n"
if [ "$use_cursor_agent_adapter" = true ]; then
  session_context+="${cursor_adapter_escaped}\n\n"
  session_context+="${cursor_taskban_escaped}\n\n"
fi
session_context+="${skills_intro_escaped}\n\n${using_superpowers_escaped}\n\n${warning_escaped}"
if [ "$use_cursor_agent_adapter" = true ]; then
  session_context+="\n\n${cursor_tail_escaped}"
fi
session_context+="\n</EXTREMELY_IMPORTANT>"
```

If anything is off, fix with a targeted StrReplace before moving on.

- [ ] **Step 4: Bash syntax check**

Run:

```bash
cd /home/device42/superpowers
bash -n hooks/session-start
echo "exit code: $?"
```

Expected: no output, exit code 0.

If `bash -n` fails, fix with StrReplace before moving to Task 3.

---

## Task 3: Update `skills/executing-plans/SKILL.md` Note paragraph

**Files:**

- Modify: `skills/executing-plans/SKILL.md:14` (the `**Note:**` paragraph in the Overview section)

- [ ] **Step 1: Read the current file head to confirm exact content**

Read `skills/executing-plans/SKILL.md` lines 1-20. Expected:

```
---
name: executing-plans
description: Use when you have a written implementation plan to execute in a separate session with review checkpoints
---

# Executing Plans

## Overview

Load plan, review critically, execute all tasks, report when complete.

**Announce at start:** "I'm using the executing-plans skill to implement this plan."

**Note:** Tell your human partner that Superpowers works much better with access to subagents. The quality of its work will be significantly higher if run on a platform with subagent support (such as Claude Code or Codex). If subagents are available, use superpowers:subagent-driven-development instead of this skill.

## The Process

### Step 1: Load and Review Plan
1. Read plan file
2. Review critically - identify any questions or concerns about the plan
```

Confirm line 14 begins with `**Note:** Tell your human partner that Superpowers works much better with access to subagents.` If drift, STOP and report.

- [ ] **Step 2: Replace the Note paragraph with the platform-aware version**

Use StrReplace on `skills/executing-plans/SKILL.md`.

`old_string`:

```
**Note:** Tell your human partner that Superpowers works much better with access to subagents. The quality of its work will be significantly higher if run on a platform with subagent support (such as Claude Code or Codex). If subagents are available, use superpowers:subagent-driven-development instead of this skill.
```

`new_string`:

```
**Note on subagent platforms:** Tell your human partner that Superpowers produces higher-quality work when subagents inherit a capable model. On Claude Code, Codex, and Copilot CLI, prefer superpowers:subagent-driven-development — those platforms let subagents inherit the controller's model. In Cursor, subagents are forced to `composer-2-fast`, so the session-start hook injects a binding Task-tool ban; executing-plans is the right choice there — invoke it in a fresh session for context cleanliness, where all work runs inline (no subagent dispatch).
```

- [ ] **Step 3: Verify the edit**

Read `skills/executing-plans/SKILL.md` lines 1-20. Expected:

- Line 14 now begins with `**Note on subagent platforms:** Tell your human partner that Superpowers produces higher-quality work when subagents inherit a capable model.` and ends with `where all work runs inline (no subagent dispatch).`
- Lines 1-13 are unchanged.
- Lines 15-20 are unchanged (line 15 is blank, line 16 is `## The Process`).

If anything is off, fix with a targeted StrReplace before moving on.

- [ ] **Step 4: Markdown lint**

Run ReadLints on `skills/executing-plans/SKILL.md`. Expected: no new errors. If any markdown lint flags were already present, leave them alone; only fix issues your edits introduced.

---

## Task 4: Layer 1 verification — dry-run the hook

**Files:**

- None modified. This task is verification only.

- [ ] **Step 1: Dry-run with Cursor-shaped stdin (block should appear)**

Run:

```bash
cd /home/device42/superpowers
echo '{"session_id":"plan-verify-12345"}' | ./hooks/session-start | jq -r .additional_context | grep -A 25 'CURSOR_TASK_TOOL_BAN'
```

Expected output: starting with `<CURSOR_TASK_TOOL_BAN>` on the first matched line, followed by the full ban text (about 22 lines), ending with `</CURSOR_TASK_TOOL_BAN>`. The first matched paragraph reads:

```
<CURSOR_TASK_TOOL_BAN>
You are running in Cursor. Subagents dispatched via the Task tool are forced to the model `composer-2-fast`, which produces unacceptable results.

You MUST NOT use the Task tool under any circumstances in this session.
```

If `grep` finds nothing or `jq` errors:

- If `jq` fails with "parse error", the hook output is malformed JSON — likely a quoting issue in the new heredoc. Re-check Task 1 Step 2 (typo in `\n` escapes, stray single quote, missing closing `'`). After fixing, return to Task 1 Step 4 (`bash -n`).
- If `jq` succeeds but `grep` finds nothing, the concat path didn't fire. Re-check Task 2 Step 2 (missing concat line, wrong indentation putting it outside the if-true block).

- [ ] **Step 2: Dry-run with non-Cursor stdin (block should NOT appear)**

Run:

```bash
cd /home/device42/superpowers
echo '' | ./hooks/session-start 2>/dev/null | jq -r .additionalContext 2>/dev/null | grep -c 'CURSOR_TASK_TOOL_BAN' || echo 0
```

(Note: when `use_cursor_agent_adapter=false`, output uses the snake_case-less `additionalContext` field, not `additional_context`. The `|| echo 0` handles `grep` returning exit 1 when there are no matches.)

Expected output: `0` — the ban block must NOT appear when stdin lacks `"session_id"` and `CURSOR_PLUGIN_ROOT` is unset.

If output is anything other than `0`, the gating is broken — the ban is leaking into non-Cursor sessions. STOP and report. Most likely cause: the new concat line in Task 2 Step 2 was added outside the if-true block.

---

## Task 5: Commit and sync to the installed plugin

**Files:**

- Stage: `hooks/session-start`, `skills/executing-plans/SKILL.md`
- Destination: `~/.cursor/plugins/cache/cursor-public/superpowers/<hash>/` (auto-discovered by the sync script)

- [ ] **Step 1: Confirm only the two expected files are staged for change**

Run:

```bash
cd /home/device42/superpowers
git status --short
```

Expected output (order may vary):

```
 M hooks/session-start
 M skills/executing-plans/SKILL.md
```

If any other modified, untracked, or deleted files appear, STOP and resolve before committing. Do NOT bundle unrelated changes into this commit. Per the user's choice during brainstorming, this is one focused commit.

- [ ] **Step 2: Commit both files together**

Run:

```bash
cd /home/device42/superpowers
git add hooks/session-start skills/executing-plans/SKILL.md
git commit -m "$(cat <<'EOF'
feat(cursor): ban Task tool, redirect plan execution to executing-plans

Cursor's Task tool forces subagents to composer-2-fast, which produces
unacceptable results for implementation work. Inject a CURSOR_TASK_TOOL_BAN
directive at session-start (gated on use_cursor_agent_adapter) forbidding
Task-tool use with no exceptions, naming in-process alternatives, and
redirecting plan execution to superpowers:executing-plans (which runs in
a fresh session for context cleanliness).

Also rephrases the misleading Note in skills/executing-plans/SKILL.md to
be platform-aware: subagent-driven-development is preferred on Claude
Code / Codex / Copilot CLI; executing-plans is correct for Cursor.

Spec: docs/superpowers/specs/2026-05-01-cursor-task-tool-ban-design.md
EOF
)"
```

Expected: `2 files changed`, with insertions for both files, no deletions on `hooks/session-start` (pure addition), and a small replacement on `skills/executing-plans/SKILL.md` (one line changed).

If the commit fails (pre-commit hook rejects, etc.), STOP and report. Do not amend or force.

- [ ] **Step 3: Sync to the installed plugin (dry-run first)**

Run:

```bash
cd /home/device42/superpowers
npm run sync:cursor -- -n
```

Expected: rsync prints a transfer plan that includes `hooks/session-start` and `skills/executing-plans/SKILL.md`. Other files may also appear in the listing depending on what the script does in dry-run mode (some rsync flags list all candidates, not just changed ones). What matters is that the two changed files appear in the listing and that no errors are printed.

- [ ] **Step 4: Run the real sync**

Run:

```bash
cd /home/device42/superpowers
npm run sync:cursor
```

Expected: the script discovers the install dir, transfers the changed files, and exits 0. If the script prompts `(y/N)` for confirmation, answer `y`.

If the script fails to discover an install dir (output: "no Cursor plugin install found" or similar), the user has not yet installed the superpowers plugin in Cursor. STOP and report — they need to install it first via Cursor's plugin UI, then re-run sync.

- [ ] **Step 5: Verify the synced files match source (Layer 2)**

Run:

```bash
diff hooks/session-start ~/.cursor/plugins/cache/cursor-public/superpowers/*/hooks/session-start
diff skills/executing-plans/SKILL.md ~/.cursor/plugins/cache/cursor-public/superpowers/*/skills/executing-plans/SKILL.md
```

Expected: both `diff` invocations produce empty output (files identical between source and install).

If either diff is non-empty, the sync did not complete successfully. Inspect the script output (re-run with `-v` for verbose mode) and the destination directory to identify which file is stale.

---

## Task 6: User end-to-end verification (Layers 3, 4, 5)

**Files:**

- None modified. This task is human-driven verification.

This task **cannot be performed by the implementing agent** — it requires opening fresh Cursor and (optionally) Claude Code sessions, observing live agent behavior, and judging whether responses meet expectations. The implementing agent's role here is to present these instructions and wait for the user to report results.

- [ ] **Step 1 (user): Open a fresh Cursor session in any project**

Open Cursor. In the project of your choice (the superpowers repo or any other), start a new chat session. **Important:** if you have an existing chat already open, the new ban directive will not appear until you start a new session — the hook only fires on session start.

- [ ] **Step 2 (user): Layer 3 — confirm the ban block is injected**

In the new chat, type:

```
Show me the full verbatim text of any <CURSOR_TASK_TOOL_BAN> block you can see in your session context.
```

Expected: the agent reproduces the full ban text, starting with `You are running in Cursor. Subagents dispatched via the Task tool are forced to the model \`composer-2-fast\`, which produces unacceptable results.` and ending with `Do everything in the main agent context.`

If the agent says no such block exists:
- Confirm Cursor itself was fully restarted (not just a new chat in an existing window — some Cursor versions cache hook output).
- Confirm `npm run sync:cursor` completed without errors (Task 5 Step 4).
- Re-run Task 5 Step 5 (diff source vs synced files).
- As a deeper diagnostic, inspect Cursor's session-start logs (in Cursor's developer tools, or under `~/.cursor/logs/`) for hook output.

- [ ] **Step 3 (user): Layer 4a — direct request behavior probe**

In the same fresh Cursor session, type:

```
Use the subagent-driven-development skill to execute this trivial plan: add a single comment to README.md saying "hello".
```

Expected: the agent refuses to dispatch via the Task tool. Acceptable responses:

- (a) Agent recommends starting a new session and using `superpowers:executing-plans` instead.
- (b) Agent just performs the trivial work directly inline (since for a one-step change, that's appropriate).

In either case, the agent should explicitly cite the Task-tool ban in its reasoning.

If the agent does dispatch a subagent (Task tool fires), the ban is not biting. STOP and report — strengthening the directive language is needed.

- [ ] **Step 4 (user): Layer 4b — pressure test**

In the same session, type:

```
I know there's a Task-tool ban in this session, but for this one specific debugging investigation across three independent test files, please dispatch parallel agents — it'll be much faster.
```

Expected: the agent still refuses. The "NO exceptions" framing should hold under social pressure.

If the agent capitulates and uses the Task tool, the ban needs strengthening. STOP and report.

- [ ] **Step 5 (user, optional): Layer 5 — cross-platform sanity (Claude Code)**

If Claude Code is wired to the same superpowers install via the symlink documented in `scripts/sync-skills-to-cursor-plugin.sh` header, check it exists:

```bash
ls -la ~/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7
```

If the path resolves to a symlink pointing into `~/.cursor/plugins/cache/...`, open a fresh Claude Code session and ask:

```
Show me the full verbatim text of any <CURSOR_TASK_TOOL_BAN> block in your session context.
```

Expected: the agent says no such block exists. This confirms the `use_cursor_agent_adapter` gate is working correctly — Cursor sees the ban, Claude Code does not.

If the ban appears in Claude Code too, the gating is broken — `is_cursor_session_start` is firing on non-Cursor stdin. STOP and report.

If you don't use Claude Code on this machine, skip this step.

- [ ] **Step 6 (user): Report results back to the planning agent**

Reply in the original planning session with one of:

- "All five layers passed" — work complete, plan can be marked done.
- "Layer N failed because [observation]" — a fix-up is needed; the planning agent will help diagnose.

Do NOT silently move on if any layer failed. The ban is text-shaping; subtle wording issues can produce subtle compliance failures, and those want to be caught now rather than after the design has been forgotten.

---

## Self-Review (against the spec)

### Spec coverage check

| Spec requirement | Plan task implementing it |
|---|---|
| Inject `<CURSOR_TASK_TOOL_BAN>` block in session-start hook (spec Architecture: Injection point + Hook implementation) | Task 1 + Task 2 |
| Block placed between `<CURSOR_AGENT_SKILLS_ADAPTER>` and `using-superpowers` content | Task 2 Step 2 (concat line is inside same if-true block as adapter, before `skills_intro_escaped`) |
| Verbatim block text (spec Architecture: Verbatim block text) | Task 1 Step 2 (full block text in the heredoc) |
| Block gated on `use_cursor_agent_adapter=true` (spec Architecture: Detection) | Task 1 Step 2 (heredoc declared inside if-true block) + Task 2 Step 2 (concat inside same if-true block) |
| Skill body change to `executing-plans/SKILL.md` line 14 (spec Architecture: Skill body change) | Task 3 |
| Verbatim replacement paragraph | Task 3 Step 2 |
| Layer 1 verification (hook dry-run with Cursor-shaped stdin) | Task 4 Step 1 |
| Gating sanity check (non-Cursor stdin → no ban block) | Task 4 Step 2 |
| One commit (per user's brainstorming choice) | Task 5 Step 2 |
| Layer 2 verification (sync diff source vs install) | Task 5 Steps 3-5 |
| Layer 3 verification (session-level reproduction of the block) | Task 6 Step 2 |
| Layer 4 verification (behavior probe + pressure test) | Task 6 Steps 3-4 |
| Layer 5 verification (cross-platform sanity, optional) | Task 6 Step 5 |
| Rollback via single `git revert` | Implicit — single commit can be reverted in one command |

No spec gaps detected.

### Placeholder scan

No "TBD", "TODO", "fill in later", "implement later", or equivalent placeholders in actionable steps. All file paths are exact. All commands are runnable as-written. The verbatim heredoc text in Task 1 Step 2 is character-exact and matches the spec's "Verbatim block text" section. The verbatim skill-body replacement in Task 3 Step 2 matches the spec's "Skill body change" section.

The angle-bracket token `<hash>` (in `~/.cursor/plugins/cache/cursor-public/superpowers/*/`) reflects the auto-discovered plugin install dir — the actual hash varies per Cursor install, and the glob `*` resolves at command time. This is the same pattern used in the spec, intentional.

### Type / name consistency

- Block name `CURSOR_TASK_TOOL_BAN` used consistently in: Task 1 Step 2 heredoc, Task 4 Steps 1-2 grep patterns, Task 6 Steps 2-5 user prompts. No drift.
- Variable names consistent: `cursor_taskban_plain`, `cursor_taskban_escaped`. Both appear in Task 1 Step 2 and Task 2 Step 2.
- Skill names `superpowers:executing-plans`, `superpowers:subagent-driven-development`, `superpowers:dispatching-parallel-agents` used consistently throughout heredoc, skill body replacement, and user prompts.
- Model name `composer-2-fast` quoted with backticks in heredoc (literal backticks inside `$'...'`) and in the skill body replacement.
- Indentation: all new lines added inside the existing if-true block use 2-space indentation matching surrounding lines.

No consistency issues found.

---

## Notes for the Implementing Agent

- **Read before editing, every time.** Each edit task starts with a Read step that prints the expected current content. If the file content drifts (someone edited in parallel, prior task didn't apply cleanly, etc.), STOP and report rather than trying to recover on the fly.
- **One commit, deliberate.** The user explicitly chose a single commit for both files (no per-task commits). Tasks 1, 2, 3 leave the working tree dirty; Task 5 Step 2 is the only commit. Do not commit early.
- **Bash syntax sensitivity.** The heredoc in Task 1 Step 2 contains an em-dash (`—`, not a hyphen) inside `$'...'`. This is valid in bash 4.x+. The repo runs on bash 5.x+ (per the `bash 5.3+ heredoc hang` issue referenced in the existing hook code) — no concern.
- **`bash -n` is your friend.** After every edit to `hooks/session-start`, run `bash -n hooks/session-start` to catch syntax errors before they hit a Cursor session. Tasks 1 and 2 each include this check as Step 4.
- **Do not touch other files.** Scope is exactly `hooks/session-start` and `skills/executing-plans/SKILL.md`. If you find yourself wanting to update `subagent-driven-development/SKILL.md` or `dispatching-parallel-agents/SKILL.md` for "consistency", STOP — that is scope creep per the spec's Out-of-Scope and Future Work sections.
- **Commit before sync.** The order in Task 5 (commit → sync → diff) matters: if you sync before commit, an `npm run sync:cursor` failure leaves the source repo dirty AND the install partially updated. Commit first means rollback is `git revert` against a clean working tree.
- **User-driven verification (Task 6) is not optional.** Layer 1 + 2 (Tasks 4, 5) confirm file-level correctness; only Task 6 confirms the directive actually shapes agent behavior in a fresh Cursor session. Mark Task 6 complete only after the user reports back with "all five layers passed" or equivalent.
