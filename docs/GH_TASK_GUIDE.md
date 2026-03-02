# gh-task CLI - GitHub Project Lifecycle Management Guide

## Overview

`gh-task` is a command-line tool that integrates GitHub Issues with Projects V2, providing a seamless workflow from issue creation to Draft PR submission. It's designed for both human developers and AI agents to manage tasks efficiently.

## Table of Contents

- [Installation](#installation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Workflow](#workflow)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [Advanced Usage](#advanced-usage)

## Installation

### Prerequisites

1. **GitHub CLI (gh)**: Install from [cli.github.com](https://cli.github.com)
2. **Git**: Installed and configured
3. **jq**: JSON processor (optional but recommended)

```bash
# Install GitHub CLI
# macOS
brew install gh

# Linux
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install gh

# Windows
choco install gh
```

### Setup in Your Project

1. **Add coding-standards as a submodule** (if not already added):

```bash
git submodule add https://github.com/c65llc/coding-standards.git .standards
git submodule update --init --recursive
```

1. **Symlink gh-task to your PATH**:

```bash
# Option 1: Project-local bin directory
mkdir -p bin
ln -s ../.standards/bin/gh-task bin/gh-task
export PATH="$PWD/bin:$PATH"

# Option 2: System-wide installation
sudo ln -s $PWD/.standards/bin/gh-task /usr/local/bin/gh-task

# Option 3: User bin directory
mkdir -p ~/bin
ln -s $PWD/.standards/bin/gh-task ~/bin/gh-task
export PATH="$HOME/bin:$PATH"
```

1. **Authenticate with GitHub**:

```bash
gh auth login
# Follow the prompts to authenticate
# Ensure you grant 'repo' and 'project' scopes
```

## Configuration

`gh-task` requires your GitHub Projects V2 information to function properly.

### Finding Your Project ID

```bash
# List your projects
gh project list --owner <your-org-or-username>

# Or use the GitHub API
gh api graphql -f query='
  query {
    user(login: "your-username") {
      projectsV2(first: 10) {
        nodes {
          id
          title
        }
      }
    }
  }
'
```

The Project ID looks like: `PVT_kwDOABCDEF`

### Configuration Methods

#### Method 1: .gemini/settings.json (Recommended for AI Agent Projects)

```bash
mkdir -p .gemini
cat > .gemini/settings.json << 'EOF'
{
  "project_id": "PVT_kwDOABCDEF",
  "status_field_id": "PVTSSF_lADOABCDEF"
}
EOF
```

#### Method 2: .gh-task.conf (Alternative)

```bash
cat > .gh-task.conf << 'EOF'
PROJECT_ID="PVT_kwDOABCDEF"
STATUS_FIELD_ID="PVTSSF_lADOABCDEF"
EOF
```

**Note**: The `status_field_id` is optional. If not provided, `gh-task` will auto-detect it from your project.

### Project V2 Requirements

Your GitHub Project V2 must have a **Status** field with the following options:

- **Todo** - For new issues
- **In Progress** - For active work
- **In Review** - For PRs under review
- **Done** - For completed work

You can customize these names, but the tool expects these as defaults. The field matching is case-insensitive.

## Commands

### gh-task create "Title"

Creates a new GitHub Issue and adds it to your Project V2 in the "Todo" column.

```bash
gh-task create "Add user authentication feature"
```

**Output**:

```text
ℹ️  Creating new issue: Add user authentication feature
✅ Created issue #42
https://github.com/owner/repo/issues/42
ℹ️  Adding issue to project...
✅ Issue added to project
✅ Project status updated to: Todo
```

### gh-task start \<id\>

Starts work on an issue by:

1. Fetching the issue title
2. Creating a branch named `task/<id>-<kebab-case-title>`
3. Checking out the branch
4. Moving the project card to "In Progress"
5. Saving the task state

```bash
gh-task start 42
```

**Output**:

```text
ℹ️  Starting work on issue #42
ℹ️  Creating branch: task/42-add-user-authentication-feature
✅ Checked out branch: task/42-add-user-authentication-feature
ℹ️  Updating project status to: In Progress
✅ Project status updated to: In Progress
✅ Started working on issue #42: Add user authentication feature
```

### gh-task status

Displays your current task status, branch information, and git status.

```bash
gh-task status
```

**Output**:

```text
═══════════════════════════════════════════════════
Current Task Status
═══════════════════════════════════════════════════

  Issue:         #42
  Branch:        task/42-add-user-authentication-feature
  Current Branch: task/42-add-user-authentication-feature

  Title:         Add user authentication feature
  State:         OPEN
  URL:           https://github.com/owner/repo/issues/42

Git Status:
 M src/auth.js
 M tests/auth.test.js

═══════════════════════════════════════════════════
```

### gh-task update "message"

Adds a progress comment to the GitHub Issue to keep your team informed.

```bash
gh-task update "Implemented login endpoint and basic authentication"
```

**Output**:

```text
ℹ️  Adding progress comment to issue #42
✅ Comment added to issue #42
```

The comment appears on GitHub as:

> **Progress Update:** Implemented login endpoint and basic authentication

### gh-task submit

Submits your work by:

1. Running validation checks (tests)
2. Committing any uncommitted changes (with confirmation)
3. Pushing the branch to remote
4. Creating a Draft Pull Request
5. Moving the project card to "In Review"
6. Clearing the task state

```bash
gh-task submit
```

**Output**:

```text
ℹ️  Submitting task for issue #42
ℹ️  Running validation checks...
ℹ️  Running npm test...
✅ Tests passed
ℹ️  Pushing branch to remote...
✅ Branch pushed to remote
ℹ️  Creating draft pull request...
✅ Draft PR created: https://github.com/owner/repo/pull/123
ℹ️  Updating project status to: In Review
✅ Project status updated to: In Review
✅ Task submitted successfully!

Next steps:
  1. Review the PR at: https://github.com/owner/repo/pull/123
  2. Mark as 'Ready for review' when complete
  3. Request reviewers
```

## Workflow

### Complete Workflow Example

```bash
# 1. Create a new issue
gh-task create "Implement password reset functionality"
# Output: Created issue #45

# 2. Start working on the issue
gh-task start 45
# Output: Checked out branch: task/45-implement-password-reset-functionality

# 3. Make your changes
vim src/auth/password-reset.js
vim tests/password-reset.test.js

# 4. Check status periodically
gh-task status

# 5. Update the team on progress
gh-task update "Completed password reset email template"

# 6. Continue work...
gh-task update "Added password reset token generation and validation"

# 7. Submit when ready
gh-task submit
# Output: Draft PR created: https://github.com/owner/repo/pull/125

# 8. On GitHub, mark PR as "Ready for review" when all checks pass
```

## Examples

### Working with Existing Issues

If you already have an issue created (e.g., from GitHub's web UI), you can start working on it directly:

```bash
# List open issues
gh issue list

# Start work on issue #10
gh-task start 10
```

### Switching Between Tasks

```bash
# You're working on issue #42
gh-task status
# Shows: Issue #42

# Need to switch to issue #50
gh-task start 50
# Prompts: Already working on issue #42. Switch to issue #50? (y/N)
# Type 'y' to switch
```

### Handling Validation Failures

```bash
gh-task submit
# Output: ❌ Error: Tests failed. Please fix before submitting.

# Fix the failing tests
vim tests/my-test.js

# Try again
gh-task submit
```

### Manual Commits Before Submit

```bash
# Make changes
vim src/feature.js

# Commit manually
git add src/feature.js
git commit -m "feat: add new feature"

# Submit (will skip commit step since everything is committed)
gh-task submit
```

## Troubleshooting

### Common Issues

#### "GitHub CLI (gh) not found"

**Problem**: The `gh` command is not installed or not in PATH.

**Solution**:

```bash
# Install gh (see Installation section above)
# Verify installation
gh --version
```

#### "Not authenticated with GitHub"

**Problem**: You haven't logged in with GitHub CLI.

**Solution**:

```bash
gh auth login
# Follow the prompts
# Ensure you grant 'repo' and 'project' scopes
```

#### "Could not determine repository information"

**Problem**: Not in a git repository or remote is not set.

**Solution**:

```bash
# Check git remote
git remote -v

# Add remote if missing
git remote add origin https://github.com/owner/repo.git
```

#### "PROJECT_ID not configured"

**Problem**: Project configuration is missing.

**Solution**:

```bash
# Create configuration file
mkdir -p .gemini
cat > .gemini/settings.json << 'EOF'
{
  "project_id": "PVT_kwDOABCDEF"
}
EOF
```

#### "Could not find status option: In Progress"

**Problem**: Your project doesn't have the expected status fields.

**Solution**:

1. Go to your GitHub Project
2. Click on the "Status" field settings
3. Ensure you have options: "Todo", "In Progress", "In Review", "Done"
4. The names are case-insensitive but should match closely

#### Tests fail during submit

**Problem**: Your test suite is failing.

**Solution**:

```bash
# Run tests manually to see the full output
npm test
# or
make test
# or
pytest

# Fix the issues, then try submit again
```

### Debug Mode

For troubleshooting, you can run `gh-task` commands with bash debugging:

```bash
bash -x $(which gh-task) start 42
```

This shows all commands being executed.

### Checking Configuration

```bash
# Check if jq is installed (recommended for JSON parsing)
command -v jq

# Check GitHub authentication
gh auth status

# Check project configuration
cat .gemini/settings.json
# or
cat .gh-task.conf

# List your projects
gh project list --owner <your-org>
```

## Advanced Usage

### Custom Validation Scripts

You can customize the validation that runs before `gh-task submit` by modifying your test scripts in `package.json`, `Makefile`, or test configuration files.

Example `package.json`:

```json
{
  "scripts": {
    "test": "jest && npm run lint && npm run type-check",
    "lint": "eslint src/",
    "type-check": "tsc --noEmit"
  }
}
```

### Environment Variables

- `GH_TASK_CONFIG`: Override default config file location

  ```bash
  GH_TASK_CONFIG=/path/to/config gh-task start 42
  ```

### Branch Naming

The default branch naming convention is `task/<id>-<kebab-case-title>`. The title is:

- Converted to lowercase
- Spaces replaced with hyphens
- Special characters removed
- Truncated to 50 characters

Example: "Fix Bug in User Authentication" → `task/42-fix-bug-in-user-authentication`

### CI/CD Integration

See [TOOLING.md](./TOOLING.md) for information on setting up GitHub Actions workflows that automatically sync project status based on PR events.

### Multiple Projects

If you work with multiple projects, you can have different configurations per repository:

```bash
# Project A
cd /path/to/project-a
cat > .gemini/settings.json << 'EOF'
{
  "project_id": "PVT_kwDOProjectA"
}
EOF

# Project B
cd /path/to/project-b
cat > .gemini/settings.json << 'EOF'
{
  "project_id": "PVT_kwDOProjectB"
}
EOF
```

## Getting Help

### Command Help

```bash
gh-task help
# or
gh-task --help
# or
gh-task -h
```

### Check Version

```bash
head -n 10 $(which gh-task)
# Shows the script header with version info
```

### Report Issues

If you encounter bugs or have feature requests, please open an issue at:
<https://github.com/c65llc/coding-standards/issues>

Include:

- The command you ran
- The error message
- Your environment (OS, gh version, git version)
- Configuration (sanitized, no sensitive info)

## Best Practices

1. **Always use `gh-task start`** instead of manually creating branches
2. **Update progress regularly** with `gh-task update` to keep your team informed
3. **Run `gh-task status`** before starting new work to ensure you're on the right task
4. **Let `gh-task submit` handle the validation** - don't skip tests
5. **Use Draft PRs** - they're automatically created as drafts so you can review before marking ready
6. **One task at a time** - complete and submit before switching to another task
7. **Commit regularly** - don't wait until submit time to commit your work

## Integration with AI Agents

For AI agent integration, see [TOOLING.md](./TOOLING.md) which provides specific instructions for AI agents using `gh-task` in automated workflows.
