---
title: "Cursor Commands"
description: "Reference for the custom Cursor slash commands included in this repository."
---

# Cursor Commands

This repository ships three custom slash commands for Cursor AI. They live in `.cursor/commands/` and are available in the Cursor chat interface after setup.

## Setup

The commands are installed automatically by `scripts/setup.sh`. If you need to install them manually:

```bash
mkdir -p .cursor/commands
cp .standards/.cursor/commands/* .cursor/commands/
```

After copying the files, **quit Cursor completely and reopen it** to load the new commands.

## Available Commands

### `/pr` -- Create a Pull Request

**File:** `.cursor/commands/pr.md`

Generates a pull request with an AI-written title and description based on your branch's commits and diffs.

**How it works:**

1. Runs `scripts/generate-pr-content.sh` to collect commit messages, changed files, and diff statistics.
2. Analyzes the output and generates a title in Conventional Commits format (e.g., `feat(auth): add OAuth2 login flow`).
3. Writes a structured PR description with summary, changes, key files, testing notes, and breaking changes.
4. Displays the generated content for your review.
5. After confirmation, creates the PR using `gh pr create`.

**Prerequisites:**

- GitHub CLI (`gh`) installed and authenticated.
- Your branch pushed to the remote.

### `/review` -- Code Review

**File:** `.cursor/commands/review.md`

Reviews the current branch against `main`, checking for correctness, standards compliance, documentation gaps, and maintainability issues.

**What it checks:**

- **Correctness:** Logic errors, edge cases, null safety, boundary conditions, race conditions.
- **Standards compliance:** Architecture layer violations, language-specific conventions, naming, error handling patterns.
- **Documentation:** Public API docs, inline comments for complex logic, CHANGELOG entries, commit message format.
- **Maintainability:** Function length (target < 30 lines), single responsibility, cyclomatic complexity, DRY principle, naming clarity.

**Output format:**

The review is presented as a structured report with:

- Summary and overall assessment.
- Issues grouped by file, each with a severity level (Must Fix, Should Fix, Nice to Have).
- Specific suggestions with code examples.
- Actionable checklist of items to address.

### `/address_feedback` -- Address PR Feedback

**File:** `.cursor/commands/address_feedback.md`

Walks you through every unresolved comment on the current pull request, one at a time.

**How it works:**

1. Fetches unresolved review threads and general comments using `scripts/fetch-pr-comments.sh`.
2. For each comment, displays the author, content, file path, line number, and surrounding code context.
3. Offers five options:
   - **Ignore** -- mark the comment as resolved and move on.
   - **Analyze** -- get an AI analysis of the concern with a suggested response.
   - **Apply Fix** -- implement the suggested change in your code.
   - **Respond** -- draft and post a reply to the comment on GitHub.
   - **Skip** -- move to the next comment without action.
4. Tracks progress and shows a summary at the end.

**Prerequisites:**

- GitHub CLI (`gh`) installed and authenticated.
- An open pull request associated with the current branch.
- `jq` installed (for parsing API responses).

## Adding Custom Commands

Create a new Markdown file in `.cursor/commands/`:

```markdown
# Command Name

Description of what this command does.

## Steps

1. First step...
2. Second step...
```

After adding the file, restart Cursor to make the command available.

## Tips

- Commands reference standards documents in `standards/` for context. If you customize the standards, the commands automatically benefit.
- The `/review` command is particularly useful before opening a PR, while `/address_feedback` is designed for after reviewers have left comments.
- Temporary files created by these commands are stored in `.standards_tmp/`, which is git-ignored.
