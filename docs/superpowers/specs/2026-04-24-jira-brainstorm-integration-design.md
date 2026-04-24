# Jira Brainstorm Integration — Design

**Status:** Approved for implementation (fork-local, not for upstream)
**Author:** Roman Zilikovich (with agent collaboration)
**Date:** 2026-04-24
**Branch:** `configuration` (will become a fork of `obra/superpowers`)

## Problem

When starting a brainstorm on work that has an existing Jira ticket, the user currently has to paste the ticket's title, description, and relevant comments into the chat by hand. This is friction, it's error-prone (people paraphrase or omit parts), and it means the brainstorming agent never sees the original phrasing or the history of prior discussion in comments.

Goal: let the user mention a Jira key in their opening brainstorm request and, with one confirmation, have the agent fetch the ticket from Jira and use it as grounding context for the rest of the brainstorm. Everything downstream of that fetch — clarifying questions, approach proposals, design presentation, spec writing, writing-plans handoff — stays exactly as it is today.

## Scope

**In scope:**

- Edit `skills/brainstorming/SKILL.md` to add an optional "step 0" pre-check that detects Jira keys, asks the user to confirm, fetches the ticket via the already-authorized Atlassian Remote MCP server, and prepends a context block to the brainstorming flow.
- Read-only Jira access: title (`summary`), description, status, issue type, and the 10 most recent comments.

**Out of scope (Future Work, see bottom):**

- Writing back to Jira from brainstorming (comments, transitions, edits).
- Pulling linked tickets, attachments, sub-tasks, or custom fields.
- Non-Jira Atlassian products (Confluence, Bitbucket, Compass).
- Support for Atlassian environments other than the already-connected `device42.atlassian.net`.

## Non-Goals

- This is not a general Atlassian integration skill. It does one thing: hydrate brainstorming context from a Jira ticket.
- This change is not for upstream contribution to `github.com/obra/superpowers`. The project's own `AGENTS.md` / `CLAUDE.md` explicitly reject third-party-dependency, domain-specific, and fork-specific changes. This modification lives in a local fork only.

## Architecture

### Authentication

The Atlassian Remote MCP server is already connected in Cursor and authorized for the user's `device42.atlassian.net` site (verified live: `atlassianUserInfo` returns the user, `getAccessibleAtlassianResources` returns the cloud site with `read:jira-work` scope). The skill does **not** manage credentials, set environment variables, or prompt for auth. It assumes MCP auth works; if a call fails, it falls back gracefully.

### Tools called

On server `plugin-atlassian-atlassian`:

- `getAccessibleAtlassianResources` — resolves the `cloudId` on first Jira fetch per session.
- `getJiraIssue` — fetches the ticket.

Required argument shape for `getJiraIssue` (verified live via a failing call that returned the validator's required-param list):

```json
{
  "cloudId": "<uuid>",
  "issueIdOrKey": "<jira-key>",
  "fields": ["summary", "description", "status", "issuetype", "comment"]
}
```

### Recognition & confirmation

Regex `\b[A-Z][A-Z0-9]+-\d+\b` scanned against the user's opening brainstorm request. If one match, agent asks:

> "I see you mentioned `D42-1234`. Want me to fetch it from Jira and include it as context for the brainstorm?"

If multiple matches, agent lists them and asks which to fetch (or all). The agent caps multi-ticket fetches at 3 in one confirmation — if the user requests more, it asks them to narrow down or pick in rounds. Only on explicit yes does it call the MCP.

### Data flow (step 0 of brainstorming)

1. Detect Jira key(s) in opening message.
2. Ask user to confirm.
3. On yes: resolve `cloudId` if not already cached for this session (call `getAccessibleAtlassianResources`; if multiple sites, ask which).
4. Call `getJiraIssue` with the fields list above.
5. Extract: `fields.summary`, `fields.description`, `fields.status.name`, `fields.issuetype.name`, `fields.comment.comments[]` (sorted by `created` desc, take top 10, reverse to oldest-first).
6. Description is used as-is — the MCP pre-renders ADF to Markdown server-side (verified live).
7. Comments come back as ADF JSON and need light flattening (see "ADF-to-text flattening" below).
8. Build the context block (format below) and present it in the conversation.
9. Continue with brainstorming's existing step 1 ("Explore project context") unchanged.

### Context block format

Exactly as the agent will present it to itself and the user:

```
## Jira context: D42-1234 (Bug · In Testing)
Title: <summary>

Description:
<fields.description verbatim — already Markdown>

Recent comments (showing 10 of <total>, oldest first):
- [2026-04-15 · Alice Chen]: <flattened comment body>
- [2026-04-18 · Bob Diaz]: <flattened comment body>
...

Note to brainstorming session: Comments on a Jira ticket often include stale ideas, discarded approaches, questions that were never answered, and decisions that were later reversed. Before acting on anything a comment says (especially "we decided to X" or "the approach is Y"), ask the user to confirm the comment is still current and correct. Treat comments as evidence of past discussion, not as requirements.
```

### ADF-to-text flattening rules (for comment bodies)

Walk the document tree depth-first. Rules:

- `text` node → emit `text` value.
- `hardBreak` → `\n`.
- Paragraph boundary → `\n\n` separator.
- `bulletList` item → `- ` prefix, one per line.
- `orderedList` item → `1. `, `2. `, … prefix.
- `codeBlock` → fenced triple-backtick block.
- `link` mark → append ` (<href>)` after the text.
- `mention` → `@<displayName>`.
- `emoji` → the emoji's `shortName` or `text` attribute, whichever is present.
- Any node type not listed → emit inner text only.
- If the body is already a plain string (some servers return that), use it directly without walking.

This covers ~95% of real-world comment content cleanly. Edge-case fidelity (tables, panels, media) is intentionally deferred — brainstorming works fine without them.

### Session state

- `cloudId` is cached in conversation context after first resolution. Not persisted to disk.
- Each new chat session re-resolves `cloudId` on the first Jira fetch. Avoids stale-org footguns.

### Read-only boundary

Even though the authorized MCP session has `write:jira-work` scope, the skill **must never** call `addCommentToJiraIssue`, `editJiraIssue`, `transitionJiraIssue`, `createJiraIssue`, `addWorklogToJiraIssue`, or `createIssueLink`. The skill is read-only by design. Writing is Future Work.

## Error handling

Every failure path acknowledges in one sentence, then continues with standard brainstorming using whatever the user typed. Never silently retries. Never fabricates ticket content.

| Failure | One-sentence acknowledgement |
|---------|------------------------------|
| Atlassian MCP unavailable | "The Atlassian MCP server isn't responding, so I can't pull the ticket. I'll brainstorm from your description." |
| Auth expired / scope missing | "Couldn't reach Jira — looks like the Atlassian MCP session needs to be re-authorized. I'll brainstorm from your description; you can re-auth and re-paste the key if you want." |
| Ticket not found / permission denied | "`<key>` either doesn't exist or I don't have permission to read it. I'll brainstorm from your description." |
| Ticket has no description AND no comments | "`<key>` has no description or comments yet. I'll brainstorm from your description." |
| Ticket has no description but has comments | Proceed normally. Don't complain. |
| Multiple sites available, user declines to pick | "No problem — I'll brainstorm from your description without the Jira context." |

## Changes to `skills/brainstorming/SKILL.md`

Three surgical edits. All other content (Process, Design-for-isolation, Working-in-existing-codebases, After-the-design, Spec-self-review, User-review-gate, Implementation handoff, Key-principles, Visual Companion) is preserved verbatim.

### Edit 1 — Checklist

Insert a new item 0 before the current item 1:

> **0. Jira key pre-check (optional)** — If the user's initial brainstorm request contains one or more Jira-shaped keys (regex `\b[A-Z][A-Z0-9]+-\d+\b`), ask whether to fetch. On yes, resolve `cloudId` and call `getJiraIssue`; prepend the result as a context block to the brainstorm. See "Jira Integration" section below. If the user declines, skipped silently. If anything fails, acknowledge and continue.

Existing items 1–9 keep their current numbers. The checklist now runs "0, 1, 2, …, 9" (10 items).

### Edit 2 — Process Flow DOT graph

Prepend one branch node before the current "Explore project context" node:

```
"Jira keys in request?" [shape=diamond];
"User confirms fetch?" [shape=diamond];
"Fetch via Atlassian MCP\n(getAccessibleAtlassianResources, getJiraIssue)" [shape=box];
"Present as context block" [shape=box];

"Jira keys in request?" -> "User confirms fetch?" [label="yes"];
"Jira keys in request?" -> "Explore project context" [label="no"];
"User confirms fetch?" -> "Fetch via Atlassian MCP\n(getAccessibleAtlassianResources, getJiraIssue)" [label="yes"];
"User confirms fetch?" -> "Explore project context" [label="no"];
"Fetch via Atlassian MCP\n(getAccessibleAtlassianResources, getJiraIssue)" -> "Present as context block";
"Present as context block" -> "Explore project context";
```

The existing flow from "Explore project context" onward is untouched.

### Edit 3 — New "Jira Integration" section at the end of the file

A self-contained section, placed after "Visual Companion". Covers:

1. Recognition regex and confirmation phrasing.
2. Two-step MCP flow (`getAccessibleAtlassianResources` → `getJiraIssue`) with the exact argument shape.
3. ADF-to-text flattening rules for comments.
4. Context-block format.
5. The "Note to brainstorming session" about comment staleness (reproduced verbatim in the skill).
6. Error-handling catalog (reproduced verbatim from the table above).
7. Read-only boundary (never call any `write:jira-work` tool from this skill).
8. Closing line: "Future work: write-back capabilities are out of scope — see the design doc's Future Work section."

## Testing (manual, 4 scenarios)

This repo does not have an automated skill-behavior test pattern, and introducing one is out of scope. Verify the change by running these four scenarios in a fresh chat session:

1. **Positive:** *"Let's brainstorm on D42-44517"* → agent confirms, fetches, shows context block with title + description + up to 10 comments + the staleness note, then proceeds into the normal brainstorming flow.
2. **No Jira key:** *"Let's brainstorm about improving our discovery pipeline"* → agent skips step 0 entirely, no mention of Jira.
3. **Key but user declines:** *"Let's brainstorm on D42-44517"*, respond "no" to the confirmation → agent proceeds without fetching, no Jira context.
4. **Invalid key:** *"Let's brainstorm on ZZZZZ-999999"* → agent confirms, fetches, gets "not found", emits the error one-liner, proceeds to normal brainstorming.

## Rollback

Single `git revert` of the edit commit. The spec doc itself is additive and stays.

## Future Work (explicitly deferred, not in scope for this implementation)

- **Write-back to Jira from brainstorming.** Post the final brainstorm conclusions / design doc link / plan as a comment on the originating ticket (`addCommentToJiraIssue`). Transition status when a design is approved or a plan is complete (`transitionJiraIssue`). Requires a separate design conversation — the triggering conditions, message shape, and user-confirmation flow need design work.
- **Linked context.** Pull parent epic, sub-tasks, and linked issues when relevant. Risks context bloat; needs an opt-in rule.
- **Other Atlassian products.** Confluence page pulls for spec-grounding, Bitbucket PR pulls for code-review grounding. Each deserves its own skill or its own skill section.
- **Multi-ticket brainstorms.** Currently the skill asks "which one" if multiple keys appear; a future version could fetch and concatenate several tickets' context for cross-ticket brainstorms.
