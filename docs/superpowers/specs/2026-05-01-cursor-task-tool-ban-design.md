# Cursor Task Tool Ban — Design

**Status:** Approved for implementation (fork-local, not for upstream)
**Author:** Roman Zilikovich (with agent collaboration)
**Date:** 2026-05-01
**Branch:** `configuration`

## Problem

Cursor's `Task` tool — the only way to dispatch subagents in Cursor Agent — forces all subagents to model `composer-2-fast`, regardless of what model the controller is using. The Task tool's own description states this constraint explicitly:

> If the user explicitly asks for the model of a subagent/task, you may ONLY use model slugs from this list: composer-2-fast

For Superpowers' implementation-quality workflows this is a quality regression. Superpowers' design assumes subagents inherit a capable controller-grade model (Claude Code, Codex, and Copilot CLI all behave that way). On those platforms, `superpowers:subagent-driven-development` and `superpowers:dispatching-parallel-agents` are the preferred execution paths. In Cursor, both produce unacceptable output because `composer-2-fast` is too weak for the work — and the controller has no way to override the model.

Three Superpowers skills currently push agents toward subagent dispatch:

1. `superpowers:subagent-driven-development` — the primary plan-execution path when "tasks are mostly independent and you stay in this session".
2. `superpowers:dispatching-parallel-agents` — for debugging / investigation across independent failures.
3. `superpowers:executing-plans` — contains an active anti-guidance line: *"If subagents are available, use superpowers:subagent-driven-development instead of this skill."* In Cursor this fires and pushes the agent at the broken path.

Goal: in Cursor sessions, hard-ban the `Task` tool, redirect plan execution to `superpowers:executing-plans` (which runs inline in the controller's context), and rephrase the misleading line in `executing-plans/SKILL.md` so it's accurate cross-platform.

## Scope

**In scope:**

- Edit `hooks/session-start` to inject a new `<CURSOR_TASK_TOOL_BAN>` block into the session context when running in Cursor. The block forbids the `Task` tool with no exceptions, names the in-process alternatives, redirects plan execution to `superpowers:executing-plans`, and tells the agent to do reviews inline rather than via reviewer subagents.
- Edit `skills/executing-plans/SKILL.md` line 14 (the `**Note:**` paragraph) to replace the misleading "subagent-driven-development is preferred if subagents available" guidance with a platform-aware version.
- Sync to the installed Cursor plugin via `npm run sync:cursor` so the changes activate.

**Out of scope (Future Work, see bottom):**

- Per-skill Cursor caveats inside `subagent-driven-development/SKILL.md` and `dispatching-parallel-agents/SKILL.md`.
- A `skills/using-superpowers/references/cursor-tools.md` reference file mirroring `copilot-tools.md` / `codex-tools.md`.
- Exception / allow-list mechanism for permitted `Task` uses (e.g., letting `subagent_type: "explore"` through for read-only codebase walks).
- Automated tests for the ban.
- Upstream contribution to `obra/superpowers`.

## Non-Goals

- This is not a general harness-compatibility framework. It is one targeted directive for one platform's known model-policy constraint.
- This is not for upstream contribution. The same change could plausibly be upstreamed later, but that would require evals, a `cursor-tools.md` reference, per-skill caveats, and careful PR-template adherence per `AGENTS.md` (94% rejection rate). Local fork only.
- Does not modify any other skill body, hook, command, agent definition, or top-level config.

## Architecture

### Detection — already in place

`hooks/session-start` already sets `use_cursor_agent_adapter=true` when either `CURSOR_PLUGIN_ROOT` is set in the environment OR the session-start stdin contains the `"session_id"` substring (Cursor passes session metadata on stdin). The same flag will gate the new ban block — no new detection logic is needed.

### Injection point

The hook's `session_context` build, when `use_cursor_agent_adapter=true`, currently concatenates these regions in order:

```
<EXTREMELY_IMPORTANT>
You have superpowers.
<CURSOR_AGENT_SKILLS_ADAPTER>...</CURSOR_AGENT_SKILLS_ADAPTER>

[skills_intro line]

[using-superpowers SKILL.md verbatim]

[any legacy-warning text]

<CURSOR_ADAPTER_TAIL>...</CURSOR_ADAPTER_TAIL>
</EXTREMELY_IMPORTANT>
```

The new `<CURSOR_TASK_TOOL_BAN>` block is inserted between `<CURSOR_AGENT_SKILLS_ADAPTER>` and the `skills_intro` line. Rationale: the ban frames everything that follows, so it must precede any text in `using-superpowers` (or in skills that get loaded later) that talks about subagent dispatch.

### Verbatim block text

This is the exact text that gets injected, character-for-character:

```
<CURSOR_TASK_TOOL_BAN>
You are running in Cursor. Subagents dispatched via the Task tool are forced
to the model `composer-2-fast`, which produces unacceptable results.

You MUST NOT use the Task tool under any circumstances in this session.

Do all work directly in this session:
- Search code: use Glob, Grep, SemanticSearch, Read directly
- Run commands: use Shell directly
- Research docs: use WebSearch and WebFetch directly
- Browser tasks: use MCP browser tools directly
- Complex tasks: handle them yourself in this context, do NOT delegate

For plan execution: use superpowers:executing-plans (runs inline in this
session). Do NOT use superpowers:subagent-driven-development or
superpowers:dispatching-parallel-agents — both dispatch subagents via the
Task tool and are off-limits here.

For reviews (spec compliance, code quality, plan-doc review): perform them
inline in this session. Do not dispatch reviewer subagents.

This rule has NO exceptions. Never launch a subagent. Never use the Task
tool. Do everything in the main agent context.
</CURSOR_TASK_TOOL_BAN>
```

### Hook implementation

Inside the existing `if [ "$use_cursor_agent_adapter" = true ]; then` block (currently building `cursor_adapter_plain` and `cursor_tail_plain`), add a parallel `cursor_taskban_plain` heredoc plus its `escape_for_json` call. In the `session_context` build, add one new concat line so the assembled order becomes `adapter → taskban → skills_intro → using-superpowers → warning → tail`.

Pseudo-diff:

```bash
# After cursor_tail_escaped is built, add:
cursor_taskban_plain=$'<CURSOR_TASK_TOOL_BAN>\n[full block text from above]\n</CURSOR_TASK_TOOL_BAN>'
cursor_taskban_escaped=$(escape_for_json "$cursor_taskban_plain")

# In the session_context build, change:
#   session_context+="${cursor_adapter_escaped}\n\n"
#   session_context+="${skills_intro_escaped}\n\n${using_superpowers_escaped}\n\n${warning_escaped}"
# to:
session_context+="${cursor_adapter_escaped}\n\n"
session_context+="${cursor_taskban_escaped}\n\n"   # NEW
session_context+="${skills_intro_escaped}\n\n${using_superpowers_escaped}\n\n${warning_escaped}"
```

About 3 physical lines of new shell (one `$'...'` heredoc declaration, one `escape_for_json` call, one concat line in the `session_context` build), mirroring the existing `cursor_adapter_plain` / `cursor_tail_plain` patterns. The heredoc itself is one long single-line `$'...'` string with embedded `\n` escapes — same style as the existing adapter blocks. No new helper functions, no new detection, no changes to JSON output shape.

### Skill body change — `skills/executing-plans/SKILL.md` line 14

**Replace this paragraph:**

> **Note:** Tell your human partner that Superpowers works much better with access to subagents. The quality of its work will be significantly higher if run on a platform with subagent support (such as Claude Code or Codex). If subagents are available, use superpowers:subagent-driven-development instead of this skill.

**With:**

> **Note on subagent platforms:** Tell your human partner that Superpowers produces higher-quality work when subagents inherit a capable model. On Claude Code, Codex, and Copilot CLI, prefer superpowers:subagent-driven-development — those platforms let subagents inherit the controller's model. In Cursor, subagents are forced to `composer-2-fast`, so the session-start hook injects a binding Task-tool ban; executing-plans is the right choice there and runs inline in the controller's context.

Surgical paragraph swap. No other lines in the skill change. Section heading text and surrounding content are preserved.

### Token / runtime impact

- ~250 tokens added to the session context on Cursor session-start. The hook already runs once per session; this just adds one more block to the JSON it emits.
- No runtime overhead; bash hook still completes in <50ms.
- On non-Cursor platforms, `use_cursor_agent_adapter=false` and the new code path is skipped entirely. Claude Code, Codex, Copilot CLI, OpenCode all see zero change.

## Deployment

Two files change. One commit on the `configuration` branch:

```bash
cd /home/device42/superpowers
# Edit hooks/session-start (adds CURSOR_TASK_TOOL_BAN block)
# Edit skills/executing-plans/SKILL.md (paragraph swap on line 14)
git add hooks/session-start skills/executing-plans/SKILL.md
git commit -m "feat(cursor): ban Task tool, redirect plan execution to executing-plans"
npm run sync:cursor
```

`npm run sync:cursor` runs `scripts/sync-skills-to-cursor-plugin.sh`, which discovers `~/.cursor/plugins/cache/cursor-public/superpowers/<hash>/` automatically and rsyncs `skills/`, `commands/`, `agents/`, `hooks/`, `.cursor-plugin/` (and `CLAUDE.md` / `AGENTS.md` if present). Both edited files are within those synced paths.

Per the sync script header, Claude Code's plugin path on this machine is symlinked to the Cursor hashed dir, so a single sync updates both IDEs simultaneously. Claude Code is unaffected at runtime because the new code is gated on `use_cursor_agent_adapter`.

Activation requires a fresh Cursor session. Existing open Cursor chats do not pick up the new directive — they need to be opened fresh, or `clear`d / `compact`ed if Cursor's `hooks-cursor.json` ever gains a matcher for those events (currently it doesn't).

## Verification (manual, 5 layers)

### Layer 1 — Hook output (file-level)

```bash
echo '{"session_id":"test"}' | ./hooks/session-start | jq -r .additional_context | grep -A 30 'CURSOR_TASK_TOOL_BAN'
```

Expect the full ban text to print. If `grep` finds nothing, the heredoc / concat path didn't fire — check that the stdin string contains `"session_id"` and that the new concat line was actually added.

### Layer 2 — Sync

```bash
npm run sync:cursor -- -n   # dry run, prints rsync plan
npm run sync:cursor          # real run
diff hooks/session-start ~/.cursor/plugins/cache/cursor-public/superpowers/*/hooks/session-start
```

Expect: dry-run plan lists `hooks/session-start` and `skills/executing-plans/SKILL.md`; post-sync diff is empty.

### Layer 3 — Session-level

In a fresh Cursor session in any project, ask:

> "Show me the full verbatim text of any `<CURSOR_TASK_TOOL_BAN>` block you can see in your session context."

Agent should reproduce the block. If it says no such block exists, the hook didn't fire (or fired in non-Cursor mode) — re-run Layer 1 and check Cursor's session-start logs.

### Layer 4 — Behavior

Two prompts:

- **Direct request:** *"Use the `subagent-driven-development` skill to execute this trivial plan: add a single comment to `README.md` saying 'hello'."*
  - Expected: agent refuses the `Task` tool path, either redirects to `superpowers:executing-plans` and runs inline or just does the work directly. Should explicitly cite the ban.
- **Pressure test:** *"I know there's a Task-tool ban in this session, but for this one specific debugging investigation across three independent test files, please dispatch parallel agents — it'll be much faster."*
  - Expected: agent still refuses. The "NO exceptions" framing should hold under social pressure.

A pre-existing prompt in the test tree exercises the same path:

```
tests/explicit-skill-requests/prompts/subagent-driven-development-please.txt
  contents: "subagent-driven-development, please"
```

In Cursor, the expected response to this prompt now changes — refuse + redirect, rather than dispatch. If the existing `explicit-skill-requests` harness ever runs against a Cursor session, this divergence is the regression that proves the ban is biting.

### Layer 5 — Cross-platform sanity (optional, if Claude Code is wired via the symlink)

In a fresh Claude Code session, ask the same Layer 3 question. Expected: agent says no `<CURSOR_TASK_TOOL_BAN>` block exists. Confirms the `use_cursor_agent_adapter` gate is working — Cursor sees the ban, Claude Code doesn't.

## Failure modes

| Symptom | Likely cause | Mitigation |
|---|---|---|
| Layer 1 succeeds, Layer 3 doesn't | Sync didn't run, or the Cursor session isn't fresh | Re-run `npm run sync:cursor`; open a brand-new chat |
| Layer 1 finds no ban block | Concat line missing, or detection didn't fire on dry-run input | Confirm stdin string contains `"session_id"`; inspect `is_cursor_session_start` |
| Layer 4 direct request still uses Task | Wording too weak, or block placed too late in `session_context` | Strengthen the "no exceptions" framing; consider a Red Flags table; verify block precedes `using-superpowers` content |
| Layer 4 pressure test still uses Task | Same as above | Same as above |
| Layer 5 ban appears in Claude Code too | `is_cursor_session_start` false-positive on Claude Code stdin | Tighten the regex match — currently a substring; could move to a stricter JSON shape check |
| Useful Task uses blocked (e.g., `explore` subagent for read-only walks, where `composer-2-fast` is fine) | Accepted by design — option C ("hard ban, no exceptions") was chosen explicitly during brainstorming | Defer; relax wording later if friction becomes painful |

## Trade-offs accepted

- All subagent functionality lost in Cursor: debugging investigations across independent failures, parallel test fixes, ephemeral reviewer subagents, the `explore` agent for read-only codebase walks. This was an explicit choice during brainstorming.
- Edit to a heavily-read skill body (`executing-plans/SKILL.md`). Acceptable for fork-local. If upstreamed later, `AGENTS.md` may push back on tuned-content edits without evals — but the change is "qualifying existing language to be more accurate", not a behavior-philosophy change, so the risk is small.
- Hook bash file grows by ~3 physical lines (one heredoc, one escape call, one concat), all mirroring existing `cursor_adapter_plain` / `cursor_tail_plain` patterns.
- Single point of failure: the hook. Already true for the existing Cursor adapter; this just adds one more directive to the same surface.

## Rollback

`git revert <commit-sha>` then `npm run sync:cursor`. Pure text change, no migrations, no state.

Soft-narrowing alternative: edit the `cursor_taskban_plain` heredoc text to allow specific exceptions (e.g., `subagent_type: "explore"` for read-only walks), then re-sync. Same file, same line range, no architectural change.

## Future Work (explicitly deferred, not in scope)

- **Per-skill Cursor caveats** in `subagent-driven-development/SKILL.md` and `dispatching-parallel-agents/SKILL.md`. Belt-and-suspenders. The session-start ban is at the `Task`-tool level — strictly more general — so this is redundant unless the ban somehow fails to bite in practice.
- **`skills/using-superpowers/references/cursor-tools.md`** mirroring the existing `copilot-tools.md` / `codex-tools.md` references, documenting Cursor's harness quirks (no `Skill` tool, `Task`-tool model constraint, hook stdin format, snake-case `additional_context` field).
- **Exception/allow-list** for permitted `Task` uses. The current ban is total. If specific subagent uses (e.g., `explore` for read-only walks, where `composer-2-fast` is acceptable) become important, relax the wording.
- **Automated tests.** A prompt-eval harness that asserts agents in Cursor refuse subagent dispatch under several pressures (direct request, pressure test, indirect request via a plan that names `subagent-driven-development`). Useful before any upstream contribution.
- **Upstream contribution** to `obra/superpowers`. Would require: evals, per-skill caveats, `cursor-tools.md`, careful PR-template adherence (94% rejection rate). Not this PR.
