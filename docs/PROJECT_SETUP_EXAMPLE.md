# Project Setup Example - Complete Walkthrough

This guide walks through setting up a complete project with gh-task and GitHub Project Lifecycle Automation from scratch.

## Scenario

You're starting a new Node.js project and want to:

1. Use coding standards from this repository
2. Set up gh-task for issue/PR workflow
3. Configure GitHub Actions for automatic project syncing
4. Enable Definition of Done quality checks

## Prerequisites

- GitHub account with organization access (or personal account)
- GitHub CLI (`gh`) installed
- Git configured locally
- Node.js installed (for this example)

## Step-by-Step Setup

### 1. Create Repository and Project

```bash
# Create new repository on GitHub
gh repo create my-org/my-project --public --clone

# Navigate to project
cd my-project

# Initialize Node.js project
npm init -y

# Create basic structure
mkdir -p src tests
echo "# My Project" > README.md
echo "node_modules/" > .gitignore
echo "console.log('Hello World');" > src/index.js
```

### 2. Create GitHub Project V2

```bash
# Create a new project (requires organization or user scope)
gh project create --owner my-org --title "My Project Board"

# Or create via web UI:
# 1. Go to https://github.com/orgs/my-org/projects
# 2. Click "New project"
# 3. Choose "Board" view
# 4. Title: "My Project Board"
```

**Configure Project Fields:**

1. Add a "Status" field (single-select) with options:
   - Todo
   - In Progress
   - In Review
   - Done

2. Note your Project ID from the URL:
   - URL: `https://github.com/orgs/my-org/projects/1`
   - Or get via CLI: `gh project list --owner my-org`
   - Example ID: `PVT_kwDOABCDEF`

### 3. Add Coding Standards Submodule

```bash
# Add submodule
git submodule add https://github.com/c65llc/coding_standards.git .standards
git submodule update --init --recursive

# Run setup script
.standards/scripts/setup.sh

# Follow prompts to configure AI agents
```

### 4. Configure gh-task

```bash
# Create bin directory for CLI tools
mkdir -p bin

# Symlink gh-task
ln -s ../.standards/bin/gh-task bin/gh-task

# Add bin to PATH (add to .bashrc or .zshrc for permanence)
export PATH="$PWD/bin:$PATH"

# Create configuration
mkdir -p .gemini
cat > .gemini/settings.json << 'EOF'
{
  "project_id": "PVT_kwDOABCDEF"
}
EOF

# Replace PVT_kwDOABCDEF with your actual Project ID

# Test gh-task
gh-task help
```

### 5. Set Up GitHub Actions Workflows

```bash
# Create workflows directory
mkdir -p .github/workflows

# Create PR lifecycle sync workflow
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
      node_version: '18'
      run_linting: true
      run_tests: true
      run_security_scan: true
    secrets:
      gh_token: ${{ secrets.GITHUB_TOKEN }}
EOF
```

### 6. Configure Repository Settings

```bash
# Set PROJECT_ID as repository variable
gh variable set PROJECT_ID --body "PVT_kwDOABCDEF" --repo my-org/my-project

# Verify it's set
gh variable list --repo my-org/my-project
```

### 7. Add Tests and Linting

```bash
# Install test dependencies
npm install --save-dev jest eslint

# Configure package.json scripts
cat > package.json << 'EOF'
{
  "name": "my-project",
  "version": "1.0.0",
  "scripts": {
    "test": "jest",
    "lint": "eslint src/"
  },
  "devDependencies": {
    "jest": "^29.0.0",
    "eslint": "^8.0.0"
  }
}
EOF

# Create basic test
cat > tests/index.test.js << 'EOF'
test('example test', () => {
  expect(true).toBe(true);
});
EOF

# Create ESLint config
cat > .eslintrc.json << 'EOF'
{
  "env": {
    "node": true,
    "es2021": true
  },
  "extends": "eslint:recommended",
  "parserOptions": {
    "ecmaVersion": 12
  }
}
EOF

# Run tests to verify
npm install
npm test
npm run lint
```

### 8. Commit Initial Setup

```bash
# Stage all files
git add .

# Commit
git commit -m "chore: initial project setup with gh-task and workflows"

# Push to main
git push origin main
```

### 9. Test the Complete Workflow

Now test the entire gh-task workflow:

#### Create an Issue

```bash
gh-task create "Add greeting function"
# Output: Created issue #1
```

#### Start Work

```bash
gh-task start 1
# Output: Checked out branch: task/1-add-greeting-function
# Check Project: Card should be in "In Progress"
```

#### Implement Feature

```bash
# Create greeting function
cat > src/greeting.js << 'EOF'
function greet(name) {
  return `Hello, ${name}!`;
}

module.exports = { greet };
EOF

# Add test
cat > tests/greeting.test.js << 'EOF'
const { greet } = require('../src/greeting');

test('greet returns greeting message', () => {
  expect(greet('World')).toBe('Hello, World!');
});
EOF

# Test locally
npm test
npm run lint

# Commit
git add .
git commit -m "feat: add greeting function"
```

#### Update Progress

```bash
gh-task update "Implemented greeting function with tests"
# Check GitHub: Comment should appear on issue #1
```

#### Submit for Review

```bash
gh-task submit
# Output: 
# - Tests passed
# - Branch pushed
# - Draft PR created: https://github.com/my-org/my-project/pull/2
# - Project status updated to "In Review"
```

#### Review on GitHub

1. **Go to Pull Requests tab**
   - Should see Draft PR #2
   - Title: "Add greeting function"
   - Body: Contains "Closes #1"

2. **Go to Project Board**
   - Card should be in "In Review" column

3. **Check Actions tab**
   - "Definition of Done" workflow should be running
   - "PR Lifecycle Management" workflow should have updated project

#### Mark Ready and Merge

```bash
# Mark PR as ready for review
gh pr ready 2

# Request review (optional)
gh pr review 2 --approve --body "LGTM!"

# Merge PR
gh pr merge 2 --squash --delete-branch

# Check Project: Card should move to "Done"
```

### 10. Verify Complete Workflow

Check that everything worked:

1. **Issue #1**: Should be closed with "Completed in #2"
2. **PR #2**: Should be merged and closed
3. **Project Board**: Card should be in "Done"
4. **Branch**: `task/1-add-greeting-function` should be deleted
5. **Main branch**: Should contain greeting function

## Directory Structure After Setup

```text
my-project/
├── .github/
│   └── workflows/
│       ├── pr-lifecycle.yml
│       └── pr-checks.yml
├── .gitignore
├── .standards/                    # Submodule
├── .gemini/
│   └── settings.json
├── bin/
│   └── gh-task -> ../.standards/bin/gh-task
├── src/
│   ├── index.js
│   └── greeting.js
├── tests/
│   ├── index.test.js
│   └── greeting.test.js
├── .eslintrc.json
├── package.json
└── README.md
```

## Common Patterns

### Daily Development Workflow

```bash
# Morning: Check assigned issues
gh issue list --assignee @me

# Start work
gh-task start 5

# Make changes, commit frequently
# ...

# Update team on progress
gh-task update "Implemented X, working on Y"

# More changes
# ...

# When ready for review
gh-task submit
```

### Working on Multiple Issues

```bash
# Working on issue #5
gh-task status
# Current Issue: #5

# Need to switch to urgent issue #8
gh-task start 8
# Prompts: Switch from #5 to #8? (y/N)

# Complete urgent issue
gh-task submit

# Switch back to original issue
git checkout task/5-original-feature
```

### Handling Test Failures

```bash
# Try to submit
gh-task submit
# Error: Tests failed

# Review test output
npm test

# Fix issues
vim src/broken-file.js

# Verify fix
npm test

# Try again
gh-task submit
# Success!
```

## Best Practices

1. **Always authenticate first**

   ```bash
   gh auth login
   ```

2. **Configure project before first use**

   ```bash
   # Set PROJECT_ID in .gemini/settings.json
   ```

3. **Use descriptive issue titles**

   ```bash
   # Good
   gh-task create "Add user authentication with JWT"
   
   # Avoid
   gh-task create "Fix bug"
   ```

4. **Commit frequently**

   ```bash
   # Don't wait until gh-task submit
   git add .
   git commit -m "feat: add login endpoint"
   ```

5. **Update progress regularly**

   ```bash
   gh-task update "Completed backend, starting frontend"
   ```

6. **Run tests before submitting**

   ```bash
   npm test
   gh-task submit
   ```

## Troubleshooting

### "PROJECT_ID not configured"

**Solution:**

```bash
# Edit configuration
vim .gemini/settings.json
# Add: {"project_id": "PVT_kwDOABCDEF"}
```

### "gh not found"

**Solution:**

```bash
# Install GitHub CLI
brew install gh  # macOS
# or see: https://cli.github.com
```

### "Not authenticated with GitHub"

**Solution:**

```bash
gh auth login
# Follow prompts
```

### Workflow not running

**Solution:**

```bash
# Check that PROJECT_ID variable is set
gh variable list --repo my-org/my-project

# Set if missing
gh variable set PROJECT_ID --body "PVT_kwDOABCDEF"
```

## Next Steps

1. **Customize workflows**: Adjust Node.js version, add more checks
2. **Add branch protection**: Require PR reviews, status checks
3. **Set up CI/CD**: Add deployment workflows
4. **Configure Dependabot**: Automatic dependency updates
5. **Add code coverage**: Integrate coverage reporting

## Resources

- [gh-task Quick Start](./GH_TASK_QUICKSTART.md)
- [gh-task Complete Guide](./GH_TASK_GUIDE.md)
- [Tooling Architecture](./TOOLING.md)
- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [GitHub Projects V2 API](https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project)

---

**Questions?** Open an issue at [github.com/c65llc/coding_standards/issues](https://github.com/c65llc/coding_standards/issues)
