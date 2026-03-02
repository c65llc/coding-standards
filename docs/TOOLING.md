# Tooling Guide - GitHub Project Lifecycle Automation

## Overview

This document describes the GitHub Project Lifecycle Automation tooling suite, designed to integrate GitHub Issues, Projects V2, and Pull Requests into a seamless workflow. The system is optimized for both human developers and AI agents.

## Architecture

```text
┌─────────────────┐
│  GitHub Issue   │
│   (Created)     │
└────────┬────────┘
         │ gh-task create
         ▼
┌─────────────────┐
│   Project V2    │
│     "Todo"      │
└────────┬────────┘
         │ gh-task start
         ▼
┌─────────────────┐      ┌─────────────────┐
│   Project V2    │◄────►│  Feature Branch │
│  "In Progress"  │      │   task/N-title  │
└────────┬────────┘      └────────┬────────┘
         │                        │
         │ Developer works        │ Commits
         │                        │
         ▼                        ▼
┌─────────────────┐      ┌─────────────────┐
│  Progress       │      │  Code Changes   │
│  Comments       │      │   + Tests       │
└─────────────────┘      └────────┬────────┘
                                  │ gh-task submit
                                  ▼
                         ┌─────────────────┐
                         │   Draft PR      │
                         │  (Auto-linked)  │
                         └────────┬────────┘
                                  │
                                  ▼
                         ┌─────────────────┐
                         │   Project V2    │
                         │  "In Review"    │
                         └────────┬────────┘
                                  │ PR approved
                                  ▼
                         ┌─────────────────┐
                         │   Project V2    │
                         │     "Done"      │
                         └─────────────────┘
```

## Components

### 1. gh-task CLI

The core command-line interface for managing the workflow.

**Location**: `bin/gh-task`

**Commands**:

| Command | Purpose | Project V2 Impact |
| ------- | ------- | ----------------- |
| `gh-task create "Title"` | Create new issue | Adds to "Todo" column |
| `gh-task start <id>` | Start working on issue | Moves to "In Progress", creates branch |
| `gh-task status` | Show current task info | Read-only status check |
| `gh-task update "msg"` | Add progress comment | No direct impact (informational) |
| `gh-task submit` | Submit for review | Creates Draft PR, moves to "In Review" |

**State Management**:

- Tracks current task in `.gh-task-state` file
- Persists issue number and branch name
- Cleared after successful submission

### 2. GitHub Actions Workflows

Reusable workflows for automation and validation.

#### lifecycle-sync.yml

**Purpose**: Automatically sync Project V2 status based on PR events

**Triggers**: PR opened, closed, merged, converted to/from draft

**Logic**:

- PR merged or closed → "Done"
- PR in draft → "In Review"
- PR ready for review → "In Review"

**Usage in Your Project**:

```yaml
# .github/workflows/pr-lifecycle.yml
name: PR Lifecycle Management

on:
  pull_request:
    types: [opened, closed, converted_to_draft, ready_for_review]

jobs:
  sync-project:
    uses: c65llc/coding_standards/.github/workflows/lifecycle-sync.yml@main
    with:
      project_id: ${{ vars.PROJECT_ID }}
    secrets:
      gh_token: ${{ secrets.GITHUB_TOKEN }}
```

#### definition-of-done.yml

**Purpose**: Enforce quality checks on PRs before marking ready

**Checks**:

- Code linting
- Test suite execution
- Code coverage
- Security scanning (dependencies, CodeQL)
- Documentation validation
- PR metadata validation

**Usage in Your Project**:

```yaml
# .github/workflows/pr-checks.yml
name: Definition of Done

on:
  pull_request:
    types: [opened, synchronize, ready_for_review]

jobs:
  quality-checks:
    uses: c65llc/coding_standards/.github/workflows/definition-of-done.yml@main
    with:
      node_version: '18'
      python_version: '3.11'
      run_linting: true
      run_tests: true
      run_security_scan: true
    secrets:
      gh_token: ${{ secrets.GITHUB_TOKEN }}
```

### 3. Configuration

#### .gemini/settings.json

Primary configuration file for AI agent projects:

```json
{
  "project_id": "PVT_kwDOABCDEF",
  "status_field_id": "PVTSSF_lADOABCDEF"
}
```

#### .gh-task.conf

Alternative configuration (bash format):

```bash
PROJECT_ID="PVT_kwDOABCDEF"
STATUS_FIELD_ID="PVTSSF_lADOABCDEF"
```

**Finding Your Project ID**:

```bash
gh project list --owner <org-name>
```

### 4. Pull Request Template

**Location**: `.github/PULL_REQUEST_TEMPLATE/default.md`

**Key Features**:

- Includes `Closes #<issue_number>` for automatic issue linking
- Structured checklist for PR quality
- Sections for description, testing, documentation
- Enforces Definition of Done checklist

## AI Agent Instructions

> **Important**: This section provides explicit instructions for AI agents (including YOLO-mode) on how to use this tooling system.

### Workflow for AI Agents

#### Step 1: Find Your Assignment

```bash
# List issues assigned to you or in "Todo" status
gh issue list --assignee @me
# or
gh issue list --label "ai-task"
```

**Output**: Note the issue number (e.g., #42)

#### Step 2: Start Work

```bash
gh-task start 42
```

This will:

1. Create branch `task/42-<title>`
2. Check out the branch
3. Move project card to "In Progress"
4. Save task state

**Never commit directly to main.** Always work on the task branch.

#### Step 3: Implement Changes

Make your code changes, following the project's coding standards.

```bash
# Make changes to files
vim src/feature.js

# Run tests as you go
npm test
```

#### Step 4: Report Progress (Optional)

Keep the team informed of significant milestones:

```bash
gh-task update "Implemented core functionality, starting on tests"
```

#### Step 5: Submit When Complete

```bash
gh-task submit
```

This will:

1. Run validation checks (tests must pass)
2. Prompt to commit any uncommitted changes
3. Push branch to remote
4. Create Draft PR with `Closes #42` in description
5. Move project card to "In Review"

**Critical**: Do not skip the validation step. Fix any failing tests before submission.

### Error Handling for AI Agents

#### Test Failures

```bash
$ gh-task submit
❌ Error: Tests failed. Please fix before submitting.
```

**Action**:

1. Review test output
2. Fix the issues
3. Run tests again: `npm test`
4. Retry: `gh-task submit`

#### Authentication Issues

```bash
$ gh-task start 42
❌ Error: Not authenticated with GitHub.
```

**Action**:

```bash
gh auth login
# Follow authentication flow
```

#### Project Configuration Missing

```bash
$ gh-task start 42
⚠️  PROJECT_ID not configured. Skipping project status update.
```

**Action**: This is a warning, not an error. The task will still work, but won't update the project board. If project integration is required:

```bash
mkdir -p .gemini
cat > .gemini/settings.json << 'EOF'
{
  "project_id": "PVT_kwDOABCDEF"
}
EOF
```

### AI Agent Best Practices

1. **Always check status before starting new work**:

   ```bash
   gh-task status
   ```

2. **One task at a time**: Complete and submit current task before starting another

3. **Run tests frequently**: Don't wait until submit time

   ```bash
   npm test  # or make test, or pytest
   ```

4. **Commit logically**: Make small, focused commits with clear messages

   ```bash
   git add src/feature.js
   git commit -m "feat: implement user authentication"
   ```

5. **Use update command**: Keep stakeholders informed

   ```bash
   gh-task update "Completed implementation, all tests passing"
   ```

6. **Never force push**: The workflow doesn't support force push operations

7. **Handle merge conflicts**: If remote has changed, pull and resolve:

   ```bash
   git pull origin main
   # Resolve conflicts
   git add .
   git commit -m "chore: resolve merge conflicts"
   ```

### Containerized Development Environment

If using a dev container (Docker/Podman), ensure:

1. **GitHub CLI is installed** in the container
2. **Authentication is configured** via `GITHUB_TOKEN` environment variable
3. **gh-task is in PATH** via symlink or direct execution

Example Dockerfile snippet:

```dockerfile
# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
    dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
    tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt update && apt install -y gh

# Symlink gh-task to PATH
RUN ln -s /workspace/.standards/bin/gh-task /usr/local/bin/gh-task

# Configure Git
RUN git config --global user.name "AI Agent" && \
    git config --global user.email "ai@example.com"
```

Example init script:

```bash
#!/bin/bash
# init-workspace.sh

# Authenticate gh CLI with token
echo "$GITHUB_TOKEN" | gh auth login --with-token

# Verify authentication
gh auth status

echo "✅ Workspace initialized"
```

## Setup Guide for Projects

### 1. Add coding_standards Submodule

```bash
git submodule add https://github.com/c65llc/coding_standards.git .standards
git submodule update --init --recursive
```

### 2. Symlink gh-task

```bash
mkdir -p bin
ln -s ../.standards/bin/gh-task bin/gh-task
echo 'export PATH="$PWD/bin:$PATH"' >> .envrc  # if using direnv
```

### 3. Configure Project

```bash
mkdir -p .gemini
cat > .gemini/settings.json << 'EOF'
{
  "project_id": "YOUR_PROJECT_ID_HERE"
}
EOF
```

### 4. Add GitHub Actions Workflows

```bash
mkdir -p .github/workflows

# Create PR lifecycle workflow
cat > .github/workflows/pr-lifecycle.yml << 'EOF'
name: PR Lifecycle Management

on:
  pull_request:
    types: [opened, closed, converted_to_draft, ready_for_review]

jobs:
  sync-project:
    uses: c65llc/coding_standards/.github/workflows/lifecycle-sync.yml@main
    with:
      project_id: ${{ vars.PROJECT_ID }}
    secrets:
      gh_token: ${{ secrets.GITHUB_TOKEN }}
EOF

# Create definition of done workflow
cat > .github/workflows/pr-checks.yml << 'EOF'
name: Definition of Done

on:
  pull_request:
    types: [opened, synchronize, ready_for_review]

jobs:
  quality-checks:
    uses: c65llc/coding_standards/.github/workflows/definition-of-done.yml@main
    with:
      run_linting: true
      run_tests: true
      run_security_scan: true
    secrets:
      gh_token: ${{ secrets.GITHUB_TOKEN }}
EOF
```

### 5. Configure GitHub Repository

1. Go to Settings → Secrets and variables → Actions
2. Add variable `PROJECT_ID` with your project ID
3. Ensure `GITHUB_TOKEN` has `project` scope (this is automatic for GitHub-hosted runners)

### 6. Configure Project V2

1. Create or open your GitHub Project
2. Add a "Status" field (single-select) with options:
   - Todo
   - In Progress
   - In Review
   - Done
3. Note the project ID from the URL or CLI

## GitHub Projects V2 API

### Status Field Configuration

The tool interacts with Projects V2 via GraphQL. Key concepts:

- **Project ID**: `PVT_kwDOABCDEF` - Unique identifier for your project
- **Field ID**: `PVTSSF_lADOABCDEF` - Unique identifier for the Status field
- **Option ID**: Auto-detected based on option name (e.g., "In Progress")
- **Item ID**: Generated when an issue is added to the project

### GraphQL Queries Used

#### Get Project Fields

```graphql
query($projectId: ID!) {
  node(id: $projectId) {
    ... on ProjectV2 {
      fields(first: 20) {
        nodes {
          ... on ProjectV2SingleSelectField {
            id
            name
            options {
              id
              name
            }
          }
        }
      }
    }
  }
}
```

#### Update Project Item Status

```graphql
mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
  updateProjectV2ItemFieldValue(
    input: {
      projectId: $projectId
      itemId: $itemId
      fieldId: $fieldId
      value: { singleSelectOptionId: $optionId }
    }
  ) {
    projectV2Item {
      id
    }
  }
}
```

## Troubleshooting

### Common Issues

#### Issue Not Added to Project

**Symptom**: `gh-task create` succeeds but issue isn't in project

**Causes**:

- PROJECT_ID not configured
- GitHub token lacks project permissions
- Project is archived

**Solutions**:

1. Verify PROJECT_ID in configuration
2. Check GitHub token scopes: `gh auth status`
3. Ensure project is active

#### Branch Already Exists

**Symptom**: `gh-task start` fails because branch exists

**Solution**:

```bash
# Delete local branch
git branch -d task/42-old-title

# Delete remote branch if needed
git push origin --delete task/42-old-title

# Try again
gh-task start 42
```

#### Tests Fail During Submit

**Symptom**: `gh-task submit` fails with test errors

**Solution**:

```bash
# Run tests manually to see full output
npm test

# Fix issues
vim src/broken-file.js

# Verify fix
npm test

# Try submit again
gh-task submit
```

### Debug Mode

```bash
# Run with debug output
bash -x $(which gh-task) start 42

# Check state file
cat .gh-task-state

# Check configuration
cat .gemini/settings.json
```

## Security Considerations

### Token Permissions

The GitHub token needs:

- `repo` - For creating issues, PRs, and pushing branches
- `project` - For updating Projects V2 status

### Secret Management

- Never commit `GITHUB_TOKEN` to repository
- Use GitHub Secrets for workflows
- Use environment variables in dev containers
- Rotate tokens periodically

### Branch Protection

Recommended branch protection rules:

- Require pull request reviews
- Require status checks (Definition of Done workflow)
- Require branches to be up to date
- Restrict force pushes
- Restrict deletions

## Performance Considerations

- GraphQL queries are paginated (first: 100 items)
- Large projects may need pagination handling
- API rate limits apply (5000 requests/hour for authenticated users)
- Consider caching project field IDs in configuration

## Future Enhancements

Potential improvements:

- Support for multiple project boards
- Custom status field names configuration
- Assignee management commands
- Label management integration
- Time tracking integration
- Automated PR review request assignment
- Integration with other project management tools

## References

- [GitHub CLI Documentation](https://cli.github.com/manual/)
- [GitHub Projects V2 API](https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-api-to-manage-projects)
- [GitHub GraphQL API](https://docs.github.com/en/graphql)
- [gh-task CLI Guide](./GH_TASK_GUIDE.md)

---

**For detailed command usage, see**: [GH_TASK_GUIDE.md](./GH_TASK_GUIDE.md)

**For AI agent-specific examples, see**: [GEMINI.md](./GEMINI.md) (if available in your project)
