# Address PR Feedback

Guide the user through resolving all unresolved comments on the current GitHub Pull Request.

## Steps

1. **Check Prerequisites:**
   - Verify GitHub CLI (`gh`) is installed: `command -v gh`
   - Get current branch: `git branch --show-current`
   - Check if there's an associated PR: `gh pr view --json number,url,title 2>/dev/null || echo "No PR found"`
   - If no PR exists, prompt user to create one first or specify PR number

2. **Fetch Unresolved Comments:**
   - Run the PR comments fetch script: `./scripts/fetch-pr-comments.sh [PR_NUMBER]` (or `.standards/scripts/fetch-pr-comments.sh` if using submodule)
   - The script will:
     * Get PR number from current branch (or use provided PR number)
     * Fetch all unresolved review threads (code comments)
     * Fetch all unresolved general PR comments
     * Save to `.standards_tmp/pr-comments-<timestamp>.json`
   - Read the generated JSON file (path is output by the script)
   - Parse and display summary: total unresolved comments, grouped by file (if applicable)
   - If script is not available, fall back to direct `gh` commands

3. **Process Each Comment:**
   For each unresolved comment, present the following information and options:

   **Display Comment Details:**
   - Comment author and timestamp
   - Comment text/content
   - File path and line number (if applicable)
   - Related code context (read the file and show surrounding lines)
   - Thread status (if part of a review thread)

   **Present Options:**
   - **a) Ignore** - Mark comment as resolved/acknowledged (skip for now)
   - **b) Analyze** - Analyze the comment and related code, suggest a response
   - **c) Apply Fix** - Implement the suggested fix or address the concern
   - **d) Respond** - Draft and post a response to the comment
   - **e) Skip** - Move to next comment (don't mark as resolved)

4. **Option Implementations:**

   **a) Ignore:**
   - Mark the comment/thread as resolved: `gh pr review <PR_NUMBER> --resolve-thread <THREAD_ID>` (if applicable)
   - Or acknowledge and move on
   - Track in progress file: `.standards_tmp/addressed-comments-<timestamp>.txt`

   **b) Analyze:**
   - Read the related file and code context
   - Analyze the comment's concern against:
     * Project standards (`standards/architecture/00_project_standards_and_architecture.md`)
     * Language-specific standards (if applicable)
     * Code review expectations (`standards/process/14_code_review_expectations.md`)
   - Suggest a response that:
     * Acknowledges the concern
     * Explains the reasoning (if the code is correct)
     * Proposes a solution (if the concern is valid)
     * References relevant standards
   - Present the suggested response to the user for review
   - Optionally proceed to option (d) to post the response

   **c) Apply Fix:**
   - Read the related file and understand the context
   - Analyze what change is needed based on the comment
   - Implement the fix following project standards:
     * Architecture patterns
     * Language-specific conventions
     * Error handling patterns
     * Testing requirements
   - Show the proposed changes to the user
   - After user confirmation, apply the changes
   - Optionally commit the fix: `git add <files> && git commit -m "fix: address review feedback on <file>"` (ask user first)
   - Optionally proceed to option (d) to respond to the comment explaining the fix

   **d) Respond:**
   - If coming from option (b), use the suggested response
   - If standalone, help draft a response:
     * Acknowledge the feedback
     * Explain the approach taken (if fix was applied)
     * Ask clarifying questions (if needed)
     * Reference relevant standards or documentation
   - Show the response to the user for review
   - After confirmation, post the response:
     * For review comments: `gh pr comment <PR_NUMBER> --body "<response>" --reply-to <COMMENT_ID>`
     * For general comments: `gh pr comment <PR_NUMBER> --body "<response>"`
   - Mark thread as resolved if appropriate (ask user)

   **e) Skip:**
   - Move to the next comment without taking action
   - Keep the comment in the list for later processing

5. **Progress Tracking:**
   - Maintain a progress file: `.standards_tmp/addressed-comments-<timestamp>.txt`
   - Track: comment ID, action taken, timestamp
   - Show progress summary: "X of Y comments addressed"
   - At the end, show summary of actions taken

6. **Completion:**
   - Display final summary:
     * Total comments processed
     * Actions taken (ignored, analyzed, fixed, responded)
     * Remaining unresolved comments (if any)
   - Suggest next steps:
     * Push commits if fixes were applied
     * Re-request review if significant changes made
     * Check for new comments

## Best Practices

- **Context First:** Always read and display the relevant code context before suggesting actions
- **Standards Alignment:** Reference project standards when analyzing comments
- **User Control:** Always confirm before posting responses or applying fixes
- **Clear Communication:** Draft responses that are professional, clear, and constructive
- **Incremental Progress:** Process comments one at a time, allowing user to review each action
- **Respectful Responses:** Acknowledge feedback even when disagreeing, explain reasoning

## Error Handling

- If GitHub CLI is not installed, provide installation instructions
- If PR is not found, help user identify the correct PR or create one
- If API rate limits are hit, inform user and suggest waiting
- If file paths in comments are invalid, inform user and skip that comment
- If user cancels, save progress and allow resuming later

