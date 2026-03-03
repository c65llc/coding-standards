# Create Pull Request

Create and populate a GitHub Pull Request from the current branch to main using Cursor AI to generate the title and body.

## Steps

1. **Gather PR Information:**
   - Run the PR content generation script: `./scripts/generate-pr-content.sh` (or `.standards/scripts/generate-pr-content.sh` if using submodule)
   - Read the generated PR content file (path is output by the script)
   - The file will be created in `.standards_tmp/` directory (which should be in `.gitignore`)
   - Analyze the commits, changed files, and code diff from the file

2. **Generate PR Content with AI:**
   - Create a clear, descriptive PR title following Conventional Commits format (e.g., `feat(scope): description`)
   - Write a comprehensive PR description that includes:
     - **Summary:** Brief overview of what changed
     - **Changes:** Detailed list of what was modified and why
     - **Files:** Key files that were changed
     - **Testing:** Testing approach or test coverage notes
     - **Breaking Changes:** Any breaking changes (if applicable)
   - Use the commit messages, file changes, and code context to create an intelligent description
   - Follow PR standards from `standards/process/proc-02_git_version_control_standards.md`

3. **Display and Execute:**
   - Show the generated title and body to the user for review
   - After user confirmation (or if auto-confirmed), execute: `PR_TITLE="<generated title>" PR_BODY="<generated body>" make pr`
   - Escape the PR_BODY properly for shell execution (handle newlines, quotes, etc.)

4. **Provide Feedback:**
   - Display the PR URL after creation
   - Show any errors if PR creation fails
   - Confirm successful PR creation

