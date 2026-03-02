# Contributing to Coding Standards

Welcome, and thank you for your interest in this project! This repository provides a
unified coding standards framework that auto-syncs to multiple AI coding assistants
(Cursor, GitHub Copilot, Claude Code/Aider, OpenAI Codex, and Gemini CLI). Your
feedback helps make these standards better for everyone.

## Reporting Issues

Found a bug, typo, or something that does not work as expected? Please open a
[GitHub Issue](https://github.com/c65llc/coding-standards/issues).

When filing an issue, include:

- A clear, descriptive title
- Steps to reproduce (if applicable)
- Which AI agent or setup step is affected
- Your environment (OS, editor, agent version)

## Requesting New Languages or Agents

Want standards for a language or AI agent we do not cover yet? Open a
[feature request issue](https://github.com/c65llc/coding-standards/issues/new) with:

- The language or agent name
- A brief description of why it would be valuable
- Any references to official style guides or conventions you recommend

We prioritize requests based on community interest, so feel free to upvote existing
requests with a thumbs-up reaction.

## Forking and Customizing

This project is designed to be forked and tailored to your organization. Here is how:

1. **Fork the repository** -- Click "Fork" on
   [github.com/c65llc/coding-standards](https://github.com/c65llc/coding-standards).

2. **Clone your fork**
   ```bash
   git clone https://github.com/YOUR_ORG/coding-standards.git
   cd coding-standards
   ```

3. **Customize standards for your team** -- Edit files under `standards/` to match
   your organization's conventions. Add or remove language standards as needed.

4. **Point the installer at your fork** -- When installing in projects, use your
   fork URL:
   ```bash
   STANDARDS_REPO_URL="https://github.com/YOUR_ORG/coding-standards" \
     curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/coding-standards/main/install.sh | bash
   ```

5. **Keep your fork updated from upstream**
   ```bash
   git remote add upstream https://github.com/c65llc/coding-standards.git
   git fetch upstream
   git merge upstream/main
   ```
   Resolve any conflicts where your customizations diverge from upstream, then push
   to your fork.

## Why We Don't Accept PRs (Yet)

This project is still new and the structure is actively stabilizing. While we
appreciate the desire to contribute code directly, we are not accepting pull requests
at this time. This lets us iterate quickly and keep the standards internally
consistent as the framework matures.

Once the project reaches a stable baseline, we plan to open up pull requests with
clear contribution guidelines. Until then, your issues and feedback are the most
valuable way to shape the project.

## Questions and Discussion

For questions, ideas, or general discussion, please open a
[GitHub Issue](https://github.com/c65llc/coding-standards/issues). There is no
separate forum or chat channel -- Issues are the central place for all community
conversation.

Thank you for helping improve coding standards for AI-assisted development!
