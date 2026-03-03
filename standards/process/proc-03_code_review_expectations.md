# Code Review Expectations

## 1. Review Process

### When to Request Review

* **All Changes:** Every PR requires at least one review before merge
* **Size:** Keep PRs focused (< 400 lines when possible). Split large changes into multiple PRs
* **Status:** Request review when code is complete, tested, and ready for feedback
* **CI Passing:** All CI checks must pass before requesting review

### Review Assignment

* **Automatic:** Use CODEOWNERS file for automatic assignment
* **Manual:** Tag relevant team members based on changed areas
* **Rotation:** Rotate reviewers to share knowledge and avoid bottlenecks

### Response Time

* **Target:** Initial review within 24-48 hours
* **Urgent:** Hotfixes and security patches within 4-8 hours
* **Communication:** Acknowledge receipt if review will be delayed

## 2. Reviewer Responsibilities

### What to Review

* **Functionality:** Does the code work as intended? Are edge cases handled?
* **Architecture:** Does it follow project architecture and design patterns?
* **Standards:** Does it meet coding standards and conventions?
* **Tests:** Are there adequate tests? Do they pass?
* **Documentation:** Is documentation updated for user-facing changes?
* **Security:** Are there security concerns or vulnerabilities?
* **Performance:** Are there obvious performance issues?

### Review Focus Areas

* **Correctness:** Logic is correct, handles edge cases, error handling is appropriate
* **Design:** Code is well-structured, follows SOLID principles, no code smells
* **Style:** Follows project style guide, consistent with codebase
* **Testing:** Adequate test coverage, tests are meaningful and maintainable
* **Documentation:** Code is documented, README updated if needed
* **Dependencies:** New dependencies are justified and secure

### Review Checklist

- [ ] Code works as described in PR description
- [ ] Follows project architecture and patterns
- [ ] Meets coding standards (formatting, naming, structure)
- [ ] **TDD was followed** — tests were written before implementation (check commit order)
- [ ] Includes appropriate tests (unit, integration, E2E, regression)
- [ ] **Test coverage is ≥ 95%** in every modified module (100% for domain)
- [ ] Bug fixes include a regression test that reproduces the original bug
- [ ] **Python code is fully typed** — `mypy --strict` passes with zero errors
- [ ] Documentation is updated (code comments, README, user docs)
- [ ] No P0/P1 security violations (see `standards/security/sec-01_security_standards.md`)
- [ ] No hardcoded secrets, API keys, or credentials in source code
- [ ] No SQL injection, command injection, or XSS vulnerabilities
- [ ] No use of banned dangerous functions with untrusted input
- [ ] No obvious performance regressions
- [ ] Dependencies are justified and up-to-date
- [ ] Git history is clean (meaningful commits)

## 3. Review Feedback

### Feedback Style

* **Constructive:** Focus on improvement, not criticism
* **Specific:** Point to exact lines and explain issues clearly
* **Actionable:** Suggest concrete improvements, not just problems
* **Respectful:** Maintain professional, friendly tone
* **Educational:** Explain "why" when suggesting changes

### Types of Feedback

* **Must Fix:** Blocking issues that must be addressed before merge
* **Should Fix:** Important improvements that should be addressed
* **Nice to Have:** Suggestions for improvement (non-blocking)
* **Questions:** Clarifications about implementation decisions

### Feedback Format

* **Inline Comments:** Use for specific lines of code
* **General Comments:** Use for broader architectural or design concerns
* **Suggestions:** Provide code examples when suggesting alternatives
* **Approval:** Explicitly approve when satisfied with changes

### Example Feedback

**Good:**

```text
This function could throw an exception if `user` is null. Consider adding a null check 
or using optional chaining: `user?.email ?? 'unknown'`
```

**Bad:**

```text
This is wrong.
```

## 4. Author Responsibilities

### PR Preparation

* **Self-Review:** Review your own code before requesting review
* **Testing:** Ensure all tests pass locally
* **Documentation:** Update relevant documentation
* **Description:** Write clear PR description explaining what, why, and how

### PR Description Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
How was this tested?

## Checklist
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] Code follows style guide
- [ ] Self-review completed
```

### Responding to Feedback

* **Acknowledge:** Acknowledge all feedback, even if you disagree
* **Clarify:** Ask questions if feedback is unclear
* **Implement:** Address "must fix" and "should fix" feedback
* **Discuss:** Engage in discussion for design decisions
* **Update:** Mark conversations as resolved when addressed

### Handling Disagreements

* **Discuss:** Engage in constructive discussion about different approaches
* **Data:** Support arguments with data, benchmarks, or examples
* **Compromise:** Be open to alternative solutions
* **Escalate:** Involve tech lead or team if unable to reach consensus

## 5. Review Approval Criteria

### Required for Approval

* **Functionality:** Code works as intended
* **Standards:** Meets project coding standards
* **TDD:** Evidence that tests were written before implementation (test commits precede implementation commits)
* **Tests:** ≥ 95% coverage in all modified modules, all tests pass, regression tests for bug fixes
* **Type Safety:** Python code passes `mypy --strict` with zero errors; TypeScript uses strict mode
* **Documentation:** Documentation is updated
* **Security:** No P0 or P1 security findings (per `standards/security/sec-01_security_standards.md`). P0/P1 findings block approval.
* **Architecture:** Follows project architecture

### Approval Types

* **Approved:** Code is ready to merge
* **Approved with Suggestions:** Ready to merge, but consider suggestions for future PRs
* **Changes Requested:** Must address feedback before merge
* **Comment:** General feedback, not blocking

### Merge Requirements

* **Minimum Approvals:** At least one approval (configurable per project)
* **CI Passing:** All CI checks must pass
* **No Blocking Comments:** All "must fix" feedback addressed
* **Up to Date:** Branch is up to date with target branch

## 6. Code Review Best Practices

### For Reviewers

* **Context:** Understand the problem being solved before reviewing
* **Empathy:** Remember that code reviews are about code, not people
* **Balance:** Find balance between thoroughness and speed
* **Learning:** Use reviews as learning opportunities for both parties
* **Praise:** Acknowledge good code and solutions

### For Authors

* **Openness:** Be open to feedback and suggestions
* **Learning:** Use reviews as learning opportunities
* **Patience:** Understand that thorough reviews take time
* **Clarity:** Provide context and explain complex decisions
* **Iteration:** Expect multiple rounds of feedback for complex changes

### Common Pitfalls to Avoid

* **Nitpicking:** Don't focus on minor style issues over functionality
* **Personal Attacks:** Keep feedback professional and code-focused
* **Perfectionism:** Don't block on minor improvements that can be addressed later
* **Rush:** Don't rush reviews or skip important checks
* **Defensiveness:** Don't take feedback personally

## 7. Automated Reviews

### CI/CD Checks

* **Linting:** Automated style and linting checks
* **Type Checking:** Type safety validation
* **Tests:** Automated test execution
* **Security:** Dependency vulnerability scanning, SAST (language-appropriate: bandit, eslint-plugin-security, brakeman, SpotBugs), secrets scanning
* **Coverage:** Code coverage reporting

### Bot Reviews

* **Dependency Updates:** Automated PRs for dependency updates
* **Code Quality:** Automated code quality checks (CodeClimate, SonarQube)
* **Documentation:** Automated documentation generation and validation

### Human Review Still Required

* **Architecture:** Design and architectural decisions
* **Business Logic:** Correctness of business logic
* **Context:** Understanding of problem and solution
* **Learning:** Knowledge sharing and team growth

## 8. Review Metrics

### Track (But Don't Obsess Over)

* **Review Time:** Time from PR creation to first review
* **Review Duration:** Time to complete review
* **Iterations:** Number of review rounds
* **Approval Rate:** Percentage of PRs approved on first review

### Goals

* **Fast Reviews:** Initial review within 24-48 hours
* **Thorough Reviews:** Catch issues before merge
* **Learning:** Improve code quality and team knowledge
* **Collaboration:** Foster positive team culture

## 9. Special Cases

### Large PRs

* **Split When Possible:** Break into smaller, focused PRs
* **Extended Timeline:** Allow more time for review
* **Incremental Review:** Review in sections if needed
* **Documentation:** Provide detailed PR description and architecture notes

### Refactoring PRs

* **Separate from Features:** Keep refactoring separate from feature changes
* **Tests First:** Ensure adequate test coverage before refactoring
* **Incremental:** Prefer small, incremental refactorings
* **Documentation:** Explain motivation and approach

### Hotfixes

* **Expedited Review:** Faster review process for critical fixes
* **Minimal Changes:** Keep changes focused on the fix
* **Testing:** Ensure fix is tested and doesn't introduce regressions
* **Documentation:** Document the issue and fix

### Security PRs

* **Confidential:** May require private review process
* **Expert Review:** Involve security experts when needed
* **Thorough Testing:** Extensive testing before merge
* **Documentation:** Document vulnerability and mitigation

## 10. Continuous Improvement

### Review Process Retrospectives

* **Regular Reviews:** Periodically review the review process itself
* **Feedback Loop:** Collect feedback from team on review process
* **Adjustments:** Make adjustments based on team needs and pain points
* **Documentation:** Keep this document updated with process improvements

### Learning and Growth

* **Pair Programming:** Use pair programming for complex changes
* **Mentoring:** Use reviews as mentoring opportunities
* **Knowledge Sharing:** Share learnings from reviews in team meetings
* **Tools:** Continuously evaluate and improve review tools and processes
