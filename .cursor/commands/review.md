# Code Review

Review the current branch against main, focusing on correctness, standards compliance, documentation, and code structure. Prioritize code maintainability and readability.

## Steps

1. **Gather Branch Information:**
   - Get current branch name: `git branch --show-current`
   - Get base branch (default: `main`)
   - Collect all changed files: `git diff --name-only main..HEAD`
   - Get full diff: `git diff main..HEAD`
   - Get commit messages: `git log main..HEAD --oneline`
   - Save this information to `.standards_tmp/review-info-<timestamp>.txt` for reference

2. **Review Focus Areas:**

   ### 1. Correctness
   - **Logic Errors:** Check for bugs, edge cases not handled, incorrect calculations
   - **Error Handling:** Verify appropriate error handling (try/catch, Result types, Option types)
   - **Null Safety:** Check for null pointer exceptions, undefined access
   - **Type Safety:** Verify types are used correctly, no unsafe casts
   - **Boundary Conditions:** Check array bounds, loop conditions, off-by-one errors
   - **State Management:** Verify state changes are correct, no race conditions
   - **Test Coverage:** Check if changes are adequately tested

   ### 2. Compliance with Standards
   - **Architecture:** Check against `standards/architecture/00_project_standards_and_architecture.md`
     - Domain → Application → Infrastructure layer dependencies
     - SOLID principles followed
     - No architecture violations
   - **Language Standards:** Check against appropriate language standards file:
     - Python: `standards/languages/03_python_standards.md`
     - Java: `standards/languages/04_java_standards.md`
     - TypeScript: `standards/languages/08_typescript_standards.md`
     - JavaScript: `standards/languages/09_javascript_standards.md`
     - Rust: `standards/languages/10_rust_standards.md`
     - (etc. for other languages)
   - **Naming Conventions:** Verify naming follows language-specific conventions
   - **Code Style:** Check formatting, indentation, spacing
   - **Error Handling Patterns:** Verify error handling follows language patterns
   - **Testing Standards:** Check test structure and coverage meet requirements

   ### 3. Appropriate Documentation
   - **Code Comments:** Public functions/classes have clear documentation
   - **Inline Comments:** Complex logic has explanatory comments
   - **README Updates:** User-facing changes have README updates
   - **API Documentation:** Public APIs are documented
   - **CHANGELOG:** User-facing changes have CHANGELOG entries (if applicable)
   - **Commit Messages:** Follow Conventional Commits format from `standards/process/13_git_version_control_standards.md`
   - **PR Description:** Clear description of what changed and why

   ### 4. Code Maintainability and Readability
   - **Function Length:** Functions should be < 50 lines (prefer < 30)
   - **Single Responsibility:** Each function does one thing
   - **Cyclomatic Complexity:** Low complexity, easy to understand
   - **Extract Methods:** Large functions should be broken into smaller functions
   - **Naming:** Function names clearly describe what they do
   - **Parameters:** Functions have reasonable number of parameters (< 5 preferred)
   - **Code Clarity:** Code is self-documenting, minimal magic numbers/strings
   - **DRY Principle:** No code duplication, extract common patterns
   - **Abstraction Levels:** Consistent abstraction levels within functions
   - **Variable Names:** Descriptive variable names that explain intent
   - **Code Organization:** Logical grouping of related code
   - **Complexity:** Identify and simplify overly complex logic

3. **Generate Review Report:**
   - Create a structured review report with:
     * **Summary:** Overview of changes and overall assessment
     * **Correctness Issues:** List any bugs, logic errors, or edge cases
     * **Standards Compliance:** List any violations of architecture or language standards
     * **Documentation Gaps:** Missing or inadequate documentation
     * **Maintainability Issues:** Functions that are too large, complex, or hard to understand
     * **Readability Issues:** Code that is unclear, poorly named, or difficult to follow
     * **Recommendations:** Specific suggestions for improvement focused on maintainability and readability

4. **Provide Actionable Feedback:**
   - For each issue, provide:
     - **File and line number** (if applicable)
     - **Issue description** (what's wrong)
     - **Why it matters** (impact/risk)
     - **Suggested fix** (how to improve)
     - **Priority** (Must Fix, Should Fix, Nice to Have)
   - Reference specific standards documents when citing violations
   - Use code examples when suggesting improvements

5. **Output Format:**
   - Present review in clear sections
   - Use checkboxes for actionable items
   - Group issues by file when possible
   - Provide summary statistics (files changed, issues found, etc.)
   - End with overall assessment and next steps

## Review Standards

Follow the review expectations from `standards/process/14_code_review_expectations.md`:
- Be constructive and specific
- Focus on code, not people
- Provide actionable feedback
- Prioritize maintainability and readability
- Focus on issues that impact long-term code quality
- Balance thoroughness with practicality

