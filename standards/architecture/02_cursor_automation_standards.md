# Document 3: Cursor AI Commands & Interaction Rules

## 1. Interaction Modes

The following keywords trigger specific behaviors. Use them at the start of a prompt.

### `@new-feature`

* **Goal:** Scaffold a new vertical slice of functionality.
* **Process:**
  1. Ask for the Feature Name.
  2. Create the `Domain` entity and logic first.
  3. Define the `Repository` interface in `Domain/Application`.
  4. Create the `DTO` in `Application`.
  5. Wait for approval before generating `Infrastructure` or `UI` code.

### `@refactor`

* **Goal:** Improve existing code without changing behavior.
* **Checks:**
  * Apply SOLID principles.
  * Extract large functions into smaller private methods.
  * Ensure Naming Conventions (Snake/Camel) are correct.
  * Remove magic numbers/strings.

### `@debug`

* **Goal:** Diagnose and fix issues.
* **Process:**
  1. Analyze the error/stack trace.
  2. Propose a hypothesis.
  3. Create a reproduction test case (if possible).
  4. Implement the fix.

### `@review`

* **Goal:** Audit code quality.
* **Action:** specific check for:
  * Architecture violations (e.g., Domain importing Infra).
  * Missing error handling.
  * Testing gaps.

## 2. Context Handling

* **File References:** Always reference the specific file path when discussing code (e.g., `packages/domain/user.py`).
* **Memory:** If a conversation spans multiple architectural layers, summarize the changes in the current context before moving to the next layer.
