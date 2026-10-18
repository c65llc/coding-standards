# Google Antigravity — Mission Isolation

Agent-specific appendix to [proc-04 Agent Workflow Standards](../../process/proc-04_agent_workflow_standards.md). The shared standard is agent-neutral; this file holds the parts that exist only because of how [Google Antigravity](https://antigravity.google.com) organises work into Missions. It applies to projects that declare `gemini` in `.standards.yml`; other agents only need the Read Protocol below.

When an agent (typically Antigravity) starts work on a major feature, it sets the active Mission URL in `.gemini/active_mission.log`. Other agents (Claude Code, Cursor, Aider, Codex, Gemini CLI) read this file and stay aligned with the Mission's scope.

## Feature Bracketing

* **One Mission per major feature.** Don't lump multiple features into one Mission — the cost is review confusion and Mission scope drift.
* **Cross-reference issue/PR.** The Mission URL should resolve to a Mission that links the work back to a GitHub Issue or PR.
* **Don't run two Missions in the same project simultaneously** — they will overwrite each other's `active_mission.log`.

## Lifecycle

```bash
./scripts/mission-set.sh https://antigravity.google.com/missions/<id>   # at start
./scripts/mission-clear.sh                                              # on completion
```

| Phase | Action |
|-------|--------|
| **Set** | Before the first agent action on the feature. Validates HTTPS-only, writes URL + UTC timestamp atomically. |
| **Active** | Other agents reading `.gemini/active_mission.log` will see the URL on first line; treat as authoritative scope. |
| **Clear** | Immediately on completion — PR merge, Mission close, or abandonment. Do not leave stale entries. |
| **Stale** | A non-empty `active_mission.log` whose timestamp is more than ~7 days old. Treat as forgotten clear; verify with the Mission owner before assuming it's still valid. |

## Read Protocol

Before starting work in a project that uses Antigravity, agents SHOULD check the file:

```bash
[ -s .gemini/active_mission.log ] && head -1 .gemini/active_mission.log
```

If a Mission URL is present, agents SHOULD reference it in commit messages and PR descriptions. Scope creep beyond the Mission's stated goals SHOULD trigger a new issue rather than expanded edits.

## Relationship to the Shared Workflow

A Mission brackets a feature; the worktree-per-task lifecycle in proc-04 §1 still applies to every task inside it. The Mission URL is additional context for commits and PRs (proc-04 §6), not a replacement for `Closes #N`.
