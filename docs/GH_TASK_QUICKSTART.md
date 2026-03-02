# gh-task Quick Start Guide

Get started with GitHub Project Lifecycle Automation in 5 minutes.

## Prerequisites

- GitHub CLI (`gh`) installed and authenticated
- Git repository with a GitHub remote
- GitHub Projects V2 board set up

## Step 1: Install gh-task (1 minute)

```bash
# Add coding-standards as submodule (if not already added)
git submodule add https://github.com/c65llc/coding-standards.git .standards

# Create bin directory and symlink
mkdir -p bin
ln -s ../.standards/bin/gh-task bin/gh-task

# Add to PATH (add this to your .bashrc or .zshrc)
export PATH="$PWD/bin:$PATH"

# Verify installation
gh-task help
```

## Step 2: Configure Your Project (2 minutes)

### Get Your Project ID

```bash
# List your GitHub Projects
gh project list --owner <your-org-or-username>

# Example output:
# NUMBER  TITLE                ID              
# 1       My Project Board     PVT_kwDOABCDEF
```

Copy the Project ID (e.g., `PVT_kwDOABCDEF`)

### Create Configuration

```bash
# Create configuration directory
mkdir -p .gemini

# Create settings file
cat > .gemini/settings.json << 'EOF'
{
  "project_id": "PVT_kwDOABCDEF"
}
EOF

# Replace PVT_kwDOABCDEF with your actual Project ID
```

### Verify Project Setup

Your GitHub Project V2 should have a **Status** field with these options:

- **Todo** - For new issues
- **In Progress** - For active work  
- **In Review** - For PRs under review
- **Done** - For completed work

## Step 3: Test the Workflow (2 minutes)

### Create an Issue

```bash
gh-task create "Test gh-task workflow"
```

Output shows issue number, e.g., `#42`

### Start Work

```bash
gh-task start 42
```

This:

- Creates branch `task/42-test-gh-task-workflow`
- Checks out the branch
- Moves project card to "In Progress"

### Make Changes

```bash
# Create a test file
echo "# Test" > TEST.md
git add TEST.md
git commit -m "test: add test file"
```

### Check Status

```bash
gh-task status
```

Shows your current task info and git status.

### Submit for Review

```bash
gh-task submit
```

This:

- Runs any tests configured in your project
- Pushes branch to remote
- Creates Draft PR linked to issue
- Moves project card to "In Review"

## Step 4: View Results

1. Go to your GitHub repository
2. Check the Pull Requests tab - you should see a new Draft PR
3. Go to your Project board - the card should be in "In Review"
4. The PR description should contain `Closes #42`

## Common Commands

```bash
# Create a new issue
gh-task create "Add user authentication"

# Start work on an issue
gh-task start 42

# Check current status
gh-task status

# Add progress update
gh-task update "Implemented login endpoint"

# Submit when ready (runs tests, creates PR)
gh-task submit

# Get help
gh-task help
```

## Next Steps

- **Add GitHub Actions**: Copy workflows from `templates/project-workflows.yml.example` to auto-sync project status
- **Read Full Guide**: See [GH_TASK_GUIDE.md](./GH_TASK_GUIDE.md) for complete documentation
- **AI Agent Setup**: See [TOOLING.md](./TOOLING.md) for AI agent integration

## Troubleshooting

### "gh not found"

Install GitHub CLI:

```bash
# macOS
brew install gh

# Linux
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update && sudo apt install gh
```

### "Not authenticated"

```bash
gh auth login
# Follow the prompts
```

### "PROJECT_ID not configured"

Edit `.gemini/settings.json` and add your Project ID:

```json
{
  "project_id": "PVT_kwDOABCDEF"
}
```

### Tests fail during submit

Run tests manually to see the error:

```bash
npm test  # or make test, or pytest
```

Fix the issues, then try `gh-task submit` again.

## Tips

1. **Always use `gh-task start`** - Don't create branches manually
2. **Check status often** - Run `gh-task status` to see where you are
3. **Update progress** - Use `gh-task update` to keep your team informed
4. **Let submit run tests** - Don't skip the validation step
5. **One task at a time** - Complete current task before starting another

## Resources

- [Complete CLI Guide](./GH_TASK_GUIDE.md)
- [Tooling Architecture](./TOOLING.md)
- [GitHub Actions Workflows](../.github/workflows/)
- [Configuration Examples](../templates/)

---

**Need help?** Open an issue at [github.com/c65llc/coding-standards/issues](https://github.com/c65llc/coding-standards/issues)
