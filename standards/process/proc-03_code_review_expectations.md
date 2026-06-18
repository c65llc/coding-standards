# Code Review Expectations

## 1. Review Process

### When to Request Review

* **All Changes:** Every PR requires at least one review before merge
* **Size:** Keep PRs focused (< 400 lines when possible). Split large changes into multiple PRs
* **Status:** Request review when code is complete, tested, and ready for feedback
* **CI Passing:** All CI checks must pass before requesting review

### Definition of Done — The Merge Loop

A PR is not "done" when the code is written. It is done when it has run the full
loop below and merged green. Follow these steps **in order** for every PR:

1. **Run the full local gate first.** Run `make ci` (the authoritative gate, in
   the right member directory for a workspace — see
   [arch-06_monorepo_workspace_standards.md](../architecture/arch-06_monorepo_workspace_standards.md)
   §3) before pushing. A partial check (`typecheck` + `lint` only) is not enough —
   run the build and coverage too.
2. **Open the PR and push.** CI runs; automated reviewers (see §7) fire on open.
3. **Wait for the automated review to post.** Do not merge before it has run.
4. **Address every comment.** All automated-reviewer findings and all human
   "must fix" / "should fix" feedback are resolved or explicitly answered.
5. **Get to all-green.** *Green means every required check passes.* A partial pass
   is a fail — "3 of 4 checks passed" is not mergeable until the 4th passes (or is
   justified and waived by policy). Resolve merge conflicts (a conflicting PR may
   run **no** checks at all — see
   [proc-02_git_version_control_standards.md](./proc-02_git_version_control_standards.md)
   §11).
6. **Merge** (squash-and-merge + delete branch is the default) **and clean up**
   the branch/worktree.

This loop is the single most important review convention: *open → automated review
fires → address all feedback → all checks green → merge.* Never merge on a partial
pass or before the automated review has run.

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
- [ ] Coverage was met by **real tests**, not by adding dead/unreachable branches to hit a number; genuinely untestable boundaries follow the untestable-boundary policy (see [core-standards.md](../shared/core-standards.md) Testing Standards) rather than being faked
- [ ] Bug fixes include a regression test that reproduces the original bug
- [ ] No soft-deleted / tombstoned records leak out of read paths (a `get` that returns deleted rows)
- [ ] Post-write side effects (cache invalidation, change notifications, index refresh, conflict/version stamping) are not skipped on any write path
- [ ] Secondary/best-effort work (mirrors, sync, telemetry) is error-isolated so one failure does not void the primary result (see [arch-05](../architecture/arch-05_resilient_architecture_patterns.md) §7)
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
* **CI Passing:** *All* CI checks pass — green means every required check, not a partial pass
* **Automated Review Addressed:** The automated reviewer (§7) has run and every finding is resolved or answered
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

### Automated Reviewers (Including AI Review)

Many repositories configure an **automated PR reviewer** (e.g. GitHub Copilot
review, Coderabbit, or another AI/code-quality bot) that posts findings when a PR
is opened. Where one is configured, treat it as a **first-class gate**, not a
nicety:

* **It fires automatically on PR open** — do not manually request it, and do not
  merge before it has run and posted.
* **Every finding is resolved or explicitly answered** before merge, the same as
  human "must fix" feedback (see §5 Merge Requirements).
* Other automated reviewers cover dependency updates (Dependabot/Renovate) and
  code-quality/documentation checks (SonarQube, CodeClimate).

The recurring findings such reviewers catch make a useful **author self-review
checklist** before pushing:

- Dead / unreachable branches (often added to chase a coverage number) — remove
  them, don't ship them.
- Soft-deleted / tombstoned records leaking out of read paths.
- A write path that skips a post-write side effect (cache invalidation, change
  notification, index refresh, version/conflict stamping).
- Best-effort/secondary work that isn't error-isolated, so one failure voids the
  whole operation.
- Reused or copy-pasted identifiers/classes that should have been factored out.

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

### PR Scoping

The goal is **one small, reviewable, independently mergeable PR per logical
change**, sequenced deliberately — not a hard line count. The `< 400 lines`
guideline is a smell threshold, not a law.

* Prefer a chain of small PRs that each merge green over one large PR. When work
  must be staged, **stack** PRs deliberately and mind the base-branch deletion
  trap (see [proc-02_git_version_control_standards.md](./proc-02_git_version_control_standards.md)
  §11 Stacked & Dependent PRs).
* Don't over-split into PRs so small they aren't independently meaningful; group
  trivially-coupled changes that must land together.

### Large PRs

* **Split When Possible:** Break into smaller, focused PRs
* **Extended Timeline:** Allow more time for review
* **Incremental Review:** Review in sections if needed
* **Documentation:** Provide detailed PR description and architecture notes

### UI PRs

* A UI change is **not auto-mergeable** without visual sign-off when no reference
  design exists for the surface. Open the PR, attach the rendered screenshots, and
  wait for human approval — even when CI is green. See
  [proc-04_agent_workflow_standards.md](./proc-04_agent_workflow_standards.md) §7
  (UI Change Validation).

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
