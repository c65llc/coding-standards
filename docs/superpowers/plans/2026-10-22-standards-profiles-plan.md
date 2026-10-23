# Standards Profiles — Implementation Plan

- **Status:** Active
- **Date:** 2026-10-22
- **Spec:** `docs/superpowers/specs/2026-10-17-standards-profiles-design.md`
- **Related:** #227

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional `profiles` list to `.standards.yml` with two profiles, `shared-core` and `ui-surface`, each delivering a block, a profile-gated skill, standards content and (for `ui-surface`) a WARN-level lint check, with no change for projects that declare nothing.

**Architecture:** A third selector axis beside `languages` and `role`, wired through the same block mapping, assembler, skill assembler, lint runner and doctor. Profile skills are gated by a `profiles:` frontmatter key read by the existing agent-neutral skill assembler. Delivered as a four-layer stack: spec, scripts, content, docs.

**Tech Stack:** bash 3.2-compatible shell, awk/sed, the repo's functional-test harness (`scripts/test-*.sh`), markdownlint, `gh stack`.

**Spec:** `docs/superpowers/specs/2026-10-17-standards-profiles-design.md`

## Global Constraints

- bash 3.2 compatible: no associative arrays, no `mapfile`, no `${var,,}`.
- Every script passes `bash -n` and ShellCheck; every new branch has a functional test.
- A project with no `profiles:` key (or `profiles: []`) is byte-for-byte unaffected in every assembled config, every skill directory, every lint result and every doctor line above INFO.
- Valid profile names are exactly `shared-core` and `ui-surface`; an unknown name is a usage error (exit 2) with the valid list in the message, before any write.
- Profile blocks are appended after the role block, in declared order, under one `## Profiles` heading with `### Shared Core` / `### UI Surface` sub-headings.
- The `web-tells` check never emits FAIL.
- **Confidentiality (spec Anti-goals):** no product, company or private-repository names; no private paths, issue, PR, defect or ADR identifiers; no quoted rulings; synthetic examples only; public attribution only. Applies to files, commit messages and PR bodies. Write clean from the start.
- Conventional Commits; one logical change per commit; each stack layer passes `make test`, `make check-agent-configs`, ShellCheck and markdownlint on its own before push.
- No `TODO` without an issue number.

## Review Focus

1. **`profiles: []` and a missing key behave identically** — Task 2.1 test: both yield empty `STD_PROFILES` and sync output identical to a baseline.
2. **A profile skill customized by the project is never deleted on un-declare** — Task 2.3 test: `customized` copy survives with a warning; `ours` copy is removed and its checksum entry dropped.
3. **Order and dedupe** — `profiles: [ui-surface, shared-core, ui-surface]` yields `profile-ui-surface.md profile-shared-core.md` — Task 2.1 test.
4. **Index-only agents** (codex, gemini, aider) list only declared-profile skills in `## Skills` — Task 2.2 test.
5. **`web-tells` on a project with no matching files is PASS, not an empty WARN** — Task 3.5 test.

---

## PR map (the stack)

| Layer | Branch | PR title | Scope |
|-------|--------|----------|-------|
| 1 | `feat/standards-profiles/01-spec` | `docs(specs): design standards profiles` | spec + this plan |
| 2 | `feat/standards-profiles/02-scripts` | `feat(scripts): add profiles selector, profile-gated skills, lint loop and doctor check` | Tasks 2.1–2.8 |
| 3 | `feat/standards-profiles/03-content` | `feat(standards): add shared-core and ui-surface profiles with arch-11 and web-tells` | Tasks 3.1–3.6 |
| 4 | `feat/standards-profiles/04-docs` | `docs: document profiles, add ADR 0002 and blog post` | Tasks 4.1–4.4 |

`Part of #227` on layers 1–3; `Closes #227` on layer 4. Each layer stands alone (spec, Decisions worth naming).

---

## Phase 1: Spec layer (`01-spec`)

### Task 1.1: Commit the plan and initialise the stack

**Files:**

- Create: `docs/superpowers/plans/2026-10-22-standards-profiles-plan.md` (this file)
- Existing: `docs/superpowers/specs/2026-10-17-standards-profiles-design.md`

- [ ] **Step 1: markdownlint both documents**

Run: `npx --yes markdownlint-cli@0.45.0 docs/superpowers/specs/2026-10-17-standards-profiles-design.md docs/superpowers/plans/2026-10-22-standards-profiles-plan.md`
Expected: no output, exit 0.

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers
git commit -m "docs(plans): add standards profiles implementation plan"
```

- [ ] **Step 3: Initialise the stack on this branch**

Run: `gh stack init feat/standards-profiles/01-spec` then `gh stack view`
Expected: one layer, `feat/standards-profiles/01-spec`, trunk `main`.

---

## Phase 2: Scripts layer (`02-scripts`)

Start with `gh stack add feat/standards-profiles/02-scripts`.

### Task 2.1: Profile vocabulary and config reading

**Files:**

- Modify: `scripts/lib/languages.sh`
- Modify: `scripts/lib/checksums.sh` (`read_standards_config`, both branches)
- Create: `scripts/test-profiles.sh`
- Modify: `Makefile` (`test-profiles` target, added to `test`), `.github/workflows/ci.yml` (step after `test-worktree-gc`)

**Interfaces:**

- Produces: `SUPPORTED_PROFILES="shared-core ui-surface"`; `profile_supported <name>` → exit 0/1; `map_profiles_to_blocks "<names>"` → `profile-<name>.md` per name, declared order, duplicates dropped, trailing space like `map_languages_to_blocks`; `profile_display_name <name>` → `Shared Core` / `UI Surface` (fallback: hyphens to spaces, each word capitalised); `STD_PROFILES` set by `read_standards_config` (empty for a missing key, `[]`, or the legacy config).

- [ ] **Step 1: Write the failing tests in `scripts/test-profiles.sh`**

Copy the harness preamble from `scripts/test-setup-safe.sh` (`pass`/`fail`/`make_project`). Tests:

```bash
# Test 1: profile_supported accepts shared-core and ui-surface, rejects foo
# Test 2: map_profiles_to_blocks "ui-surface shared-core ui-surface" == "profile-ui-surface.md profile-shared-core.md "
# Test 3: profile_display_name shared-core == "Shared Core"; ui-surface == "UI Surface"
# Test 4: read_standards_config: inline `profiles: [shared-core, ui-surface]` → STD_PROFILES="shared-core ui-surface"
# Test 5: read_standards_config: block list → same
# Test 6: read_standards_config: no key → STD_PROFILES=""; `profiles: []` → ""
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash scripts/test-profiles.sh`
Expected: Tests 1–6 ✗ (functions undefined / variable empty).

- [ ] **Step 3: Implement in `scripts/lib/languages.sh` and `scripts/lib/checksums.sh`**

`STD_PROFILES=$(yaml_list "profiles" "$yml" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')` in the yml branch; `STD_PROFILES=""` in the legacy branch.

- [ ] **Step 4: Run to verify they pass; wire into `make test` and CI**

Run: `bash scripts/test-profiles.sh && make test-profiles`
Expected: all ✓.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/languages.sh scripts/lib/checksums.sh scripts/test-profiles.sh Makefile .github/workflows/ci.yml
git commit -m "feat(lib): add profiles vocabulary, block mapping and config reading"
```

### Task 2.2: Config assembler learns `profile-` blocks and filters the skills index

**Files:**

- Modify: `scripts/assemble-config.sh` (option parser lines 26–45; `derive_name` ~155; extra-blocks loop ~225–245; skills index ~250)
- Modify: `scripts/lib/skills.sh` (`render_skills_index` gains an optional third argument)
- Test: `scripts/test-profiles.sh`

**Interfaces:**

- Consumes: `profile_display_name` (Task 2.1).
- Produces: `assemble-config.sh [--profiles "<names>"] <agent> <blocks-dir> <base-template> <output> [blocks…]`; `--profiles` defaults to `${STANDARDS_PROFILES:-}`; `skill_profiles <file>` → space-separated names from a `profiles:` scalar accepting `a`, `a, b`, `[a, b]`; `skill_applies <file> "<declared>"` → 0 when the skill has no `profiles:` key or any declared name matches; `render_skills_index <dir> <ref> ["<declared>"]` skips skills that do not apply.

- [ ] **Step 1: Write the failing tests**

Fixture: a temp blocks dir with `role-app.md`, `profile-shared-core.md`, `profile-ui-surface.md` (one line each); a temp skills dir with `plain.md` (no profiles key) and `gated.md` (`profiles: ui-surface`); base template `standards/agents/codex/base-codex.md` (whichever exists for codex).

```bash
# Test 7: one profile block → output has "## Profiles" once, then "### Shared Core", and "## Profiles" comes after "## Project Type"
# Test 8: two profile blocks → "## Profiles" exactly once; "### Shared Core" before "### UI Surface" when passed in that order
# Test 9: no WARNING line on stderr for profile- blocks
# Test 10: codex output with --profiles "" lists "### plain" and not "### gated" under "## Skills"
# Test 11: codex output with --profiles "ui-surface" lists both
# Test 12: STANDARDS_PROFILES=ui-surface in the environment behaves like --profiles
# Test 13: skill_profiles on `profiles: [a, b]`, `profiles: a, b`, `profiles: a` → "a b", "a b", "a"
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash scripts/test-profiles.sh`
Expected: 7–13 ✗ (unknown-prefix WARNING, gated listed, flag rejected).

- [ ] **Step 3: Implement**

In the extra-blocks loop add a `profile-*` branch mirroring `lang-*`: `profiles_header_printed` guard, `append_block "$block_path" "## Profiles" "### $(profile_display_name "$name")"`. `derive_name` also strips `profile-`. The skills-index call passes `"$PROFILES"` as the third argument.

- [ ] **Step 4: Run to verify they pass**

Run: `bash scripts/test-profiles.sh`
Expected: all ✓.

- [ ] **Step 5: Commit**

```bash
git add scripts/assemble-config.sh scripts/lib/skills.sh scripts/test-profiles.sh
git commit -m "feat(assemble): render profile blocks and filter the skills index by profile"
```

### Task 2.3: Skill assembler gates and removes by profile

**Files:**

- Modify: `scripts/assemble-skills.sh` (option parser; per-agent loop ~140–200)
- Modify: `scripts/lib/checksums.sh` (`remove_checksum_entry`)
- Test: `scripts/test-profiles.sh`

**Interfaces:**

- Consumes: `skill_applies`, `skill_profiles` (Task 2.2); `ownership`, `record_hash` (existing).
- Produces: `assemble-skills.sh [--profiles "<names>"] …`; `remove_checksum_entry <key> <content>` → content without that key's line, via stdout. Summary line gains `, N removed` when non-zero.

- [ ] **Step 1: Write the failing tests**

```bash
# Test 14: --profiles "" installs plain.md and not gated.md for claude-code
# Test 15: --profiles "ui-surface" installs both; .standards-checksums has an entry for .claude/skills/gated/SKILL.md
# Test 16: after Test 15, --profiles "" removes .claude/skills/gated/SKILL.md, drops its checksum line, prints "removed"; plain.md untouched
# Test 17: after Test 15, edit gated SKILL.md, then --profiles "" → file kept, stderr contains "no longer managed", checksum entry kept
# Test 18: --dry-run --profiles "" after Test 15 prints "[dry-run] Would remove: …gated/SKILL.md" and the file still exists
# Test 19: cursor and copilot targets follow the same gate (.cursor/commands/gated.md absent with --profiles "")
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash scripts/test-profiles.sh`
Expected: 14–19 ✗.

- [ ] **Step 3: Implement**

In the per-skill loop: `if ! skill_applies "$src" "$PROFILES"; then` → if `$dest` exists: `ours` → remove (or announce in dry-run), `remove_checksum_entry`, `removed=$((removed+1))`; `customized`/`foreign` → warn `"$rel is no longer managed (profile not declared) — left as is"`; `continue`.

- [ ] **Step 4: Run to verify they pass**

Run: `bash scripts/test-profiles.sh && bash scripts/test-setup-safe.sh`
Expected: all ✓ (the existing #194 tests still pass because no shipped skill has a `profiles:` key yet).

- [ ] **Step 5: Commit**

```bash
git add scripts/assemble-skills.sh scripts/lib/checksums.sh scripts/test-profiles.sh
git commit -m "feat(skills): install and remove skills by declared profile"
```

### Task 2.4: sync and diff select profile blocks and pass profiles through

**Files:**

- Modify: `scripts/sync-standards.sh` (top-level config read near `ROLE`/`DETECTED_LANGS`; block args ~158–168; skills call ~299–304)
- Modify: `scripts/diff-standards.sh` (block args ~186–195)
- Test: `scripts/test-profiles.sh`

**Interfaces:**

- Consumes: `STD_PROFILES`, `profile_supported`, `map_profiles_to_blocks` (Task 2.1).
- Produces: top-level `PROFILES` in both scripts; `export STANDARDS_PROFILES="$PROFILES"` before any assembly; `assemble-skills.sh … --profiles "$PROFILES"`.

- [ ] **Step 1: Write the failing tests**

Drive `scripts/sync-standards.sh` the way `scripts/test-setup-safe.sh` drives `setup.sh` (temp project, `claude-code` and `codex` agents, a `.standards.yml` written by the test). Because the real blocks dir has no `profile-*.md` yet in this layer, point the test at a fixture blocks dir if the script supports it; otherwise assert the warning path:

```bash
# Test 20: profiles: [shared-core] with no profile-shared-core.md in blocks → stderr "profile block profile-shared-core.md not found; skipping", exit 0, CLAUDE.md assembled
# Test 21: profiles: [bogus] → exit 2, message contains "Unknown profile: bogus (expected one of: shared-core, ui-surface)", no file written
# Test 22: profiles: [ui-surface] → assemble-skills invoked with --profiles ui-surface (assert via a stub assemble-skills.sh on PATH or by the gated-skill fixture landing)
# Test 23: diff-standards.sh with profiles declared exits 0 and does not warn about an unknown block prefix
# Test 23b: a project with no profiles key and the same project with `profiles: []` assemble byte-identical CLAUDE.md and AGENTS.md
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash scripts/test-profiles.sh`
Expected: 20–23 ✗.

- [ ] **Step 3: Implement**

Validation loop after reading config: unknown → `echo "ERROR: Unknown profile: $p (expected one of: ${SUPPORTED_PROFILES// /, })" >&2; exit 2`. Block loop: `for b in $(map_profiles_to_blocks "$PROFILES"); do [ -f "$BLOCKS_DIR/$b" ] && BLOCK_ARGS+=("$b") || echo "⚠️  profile block $b not found; skipping" >&2; done`.

- [ ] **Step 4: Run to verify they pass**

Run: `bash scripts/test-profiles.sh && bash scripts/test-bootstrap.sh`
Expected: all ✓.

- [ ] **Step 5: Commit**

```bash
git add scripts/sync-standards.sh scripts/diff-standards.sh scripts/test-profiles.sh
git commit -m "feat(sync): select profile blocks and pass profiles to the assemblers"
```

### Task 2.5: `setup.sh --profiles`

**Files:**

- Modify: `scripts/setup.sh` (flags ~105–160; validation ~215–235; `PRESERVED_YML` keys ~696; `.standards.yml` write ~704–740; `install_agent_skills` ~855)
- Test: `scripts/test-setup-safe.sh` (append)

**Interfaces:**

- Produces: `--profiles <a,b>` and `--profiles=<a,b>`; `PROFILES_OVERRIDE`; written stanza `profiles:` with one list item per profile, or the commented stanza below when none; re-running setup without the flag preserves a declared `profiles:` block (add `profiles` to the `PRESERVED_YML` key list only when `PROFILES_OVERRIDE` is empty).

Commented stanza when none:

```yaml
# Optional profiles — cross-cutting standards a project opts in to
# (shared-core: one logic core under native shells; ui-surface: platform-feel audit).
# profiles:
#   - shared-core
#   - ui-surface
```

- [ ] **Step 1: Write the failing tests (append to `test-setup-safe.sh`)**

```bash
# Test N: setup.sh --profiles shared-core,ui-surface writes "profiles:" then "  - shared-core" then "  - ui-surface"
# Test N+1: setup.sh --profiles bogus → exit 2, "Unknown profile: bogus (expected one of: shared-core, ui-surface)"
# Test N+2: setup.sh --profiles "shared-core, ,ui-surface" → exit 2 "contains an empty profile name"
# Test N+3: setup.sh with no flag writes the commented stanza
# Test N+4: a project with profiles: [ui-surface] re-run with setup.sh (no flag) keeps the block
# Test N+5: --dry-run --profiles ui-surface prints the would-write and writes nothing
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash scripts/test-setup-safe.sh`
Expected: the new tests ✗ (`Unknown option: --profiles`).

- [ ] **Step 3: Implement** mirroring the `--agents` field-by-field validation (`trim_ws`, `usage_error`).

- [ ] **Step 4: Run to verify they pass**

Run: `bash scripts/test-setup-safe.sh`
Expected: all ✓.

- [ ] **Step 5: Commit**

```bash
git add scripts/setup.sh scripts/test-setup-safe.sh
git commit -m "feat(setup): add --profiles and persist the profiles stanza"
```

### Task 2.6: Lint runner runs profile checks

**Files:**

- Modify: `scripts/lint-standards.sh` (top-level `PROFILES` beside `LANGUAGES` ~194–199; per-member read ~401–410; a third loop after the language loop ~448–455)
- Test: `scripts/test-lint-standards.sh` (append; use `LINT_CHECKS_DIR` with a fixture tree)

**Interfaces:**

- Produces: for each declared profile `p`, every `$CHECKS_DIR/profiles/$p/*.sh` runs through `run_check` with `LINT_MEMBER_EXCLUDE` set like a language check; an absent directory is skipped silently. Members read their own `profiles:`.

- [ ] **Step 1: Write the failing tests**

Fixture `LINT_CHECKS_DIR` containing `common/` (empty), `profiles/ui-surface/stub.sh` printing `WARN stub ran`.

```bash
# Test N: profiles: [ui-surface] → text output contains "WARN stub ran"
# Test N+1: no profiles key → output does not contain "stub"
# Test N+2: profiles: [shared-core] (no directory) → exit 0, no "stub", no error
# Test N+3: --format json with the stub → valid JSON containing "stub"
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash scripts/test-lint-standards.sh`
Expected: the new tests ✗.

- [ ] **Step 3: Implement**

- [ ] **Step 4: Run to verify they pass**

Run: `bash scripts/test-lint-standards.sh`
Expected: all ✓.

- [ ] **Step 5: Commit**

```bash
git add scripts/lint-standards.sh scripts/test-lint-standards.sh
git commit -m "feat(lint): run lint-checks/profiles/<profile> for declared profiles"
```

### Task 2.7: `detect-profiles.sh` and `doctor` `check_profiles`

**Files:**

- Create: `scripts/detect-profiles.sh`
- Modify: `scripts/doctor.sh` (`check_profiles` after `check_languages`; call list ~1009)
- Test: `scripts/test-profiles.sh`

**Interfaces:**

- Produces: `detect-profiles.sh [/path]` prints `<profile>\t<reason>` lines, each profile at most once, exit 0. Reasons: `uniffi in Cargo.toml`, `wasm-bindgen in Cargo.toml`, `crates/ or core/ beside platform shells`, `web app manifest`, `role: app`, `UI framework import (SwiftUI|Compose|Flutter|WinUI)`. `check_profiles`: unknown declared → `check_fail "Profiles" "Unknown profile '<x>'" "Valid: shared-core, ui-surface"`; declared but `.claude/skills/<x>/SKILL.md` missing while `claude-code` is in `STD_AGENTS` → `check_warn … "run make sync-standards"`; detected not declared → `check_info "Profiles" "<x> looks applicable (<reason>) — declare it under profiles: to opt in"`; otherwise `check_pass "Profiles" "…"`.

- [ ] **Step 1: Write the failing tests**

```bash
# Test 24: empty project → detect prints nothing
# Test 25: Cargo.toml with `uniffi = "0.29"` → "shared-core<TAB>uniffi in Cargo.toml"
# Test 26: crates/ + shells/ + apps/ → shared-core once
# Test 27: manifest.webmanifest → "ui-surface<TAB>web app manifest"; role: app in .standards.yml → ui-surface once
# Test 28: doctor with profiles: [bogus] → output contains "FAIL" and "Unknown profile 'bogus'"
# Test 29: doctor with profiles: [ui-surface], agents: [claude-code], no skill dir → WARN line mentions sync-standards
# Test 30: doctor with uniffi Cargo.toml and no profiles → INFO line contains "shared-core looks applicable"; exit status unchanged from a project without it
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash scripts/test-profiles.sh`
Expected: 24–30 ✗.

- [ ] **Step 3: Implement**

- [ ] **Step 4: Run to verify they pass**

Run: `bash scripts/test-profiles.sh && bash -n scripts/detect-profiles.sh && shellcheck scripts/detect-profiles.sh scripts/doctor.sh`
Expected: all ✓, no ShellCheck findings.

- [ ] **Step 5: Commit**

```bash
git add scripts/detect-profiles.sh scripts/doctor.sh scripts/test-profiles.sh
git commit -m "feat(doctor): suggest and check declared profiles"
```

### Task 2.8: Layer gate and changelog line

**Files:**

- Modify: `CHANGELOG.md` (`[Unreleased]` → `### Added`)

- [ ] **Step 1: Add the entry**

Entry text: **Profiles (#227):** optional profiles list in .standards.yml (shared-core, ui-surface); profile blocks assemble under a Profiles heading; skills with a profiles frontmatter key install only when declared and are removed when un-declared if unmodified; lint-standards runs lint-checks/profiles/PROFILE/; doctor checks and suggests profiles; setup.sh gains --profiles. (Format it with code spans in the changelog itself.)

- [ ] **Step 2: Run the full layer gate**

Run: `make test && make check-agent-configs && shellcheck scripts/*.sh scripts/lib/*.sh && npx --yes markdownlint-cli@0.45.0 'standards/**/*.md' 'docs/**/*.md' '*.md' --ignore REVIEW.md && ./scripts/lint-standards.sh .`
Expected: every suite ✓; no FAIL lines from the dogfood lint.

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): record the profiles selector"
```

---

## Phase 3: Content layer (`03-content`)

Start with `gh stack add feat/standards-profiles/03-content`.

### Task 3.1: `arch-07` gains tenets, decision tree and native-shell audit

**Files:**

- Modify: `standards/architecture/arch-07_cross_platform_shared_core_standards.md` (new §7, §8, §9 after §6)

- [ ] **Step 1: Write §7 Tenets** — ten numbered tenets, each: bold short name, one tension sentence, one resolution sentence, one "cite as" form (`T3 — inject ambient inputs`):

1. Seam below the UI: logic once, rendering per platform.
2. One core, many shells: a behavior difference between platforms is a bug.
3. Inject ambient inputs: clock, ids, locale, timezone come from the shell.
4. Coarse serializable facade: shells never reach past it.
5. Golden vectors are the parity gate, replayed through the FFI.
6. Generated artifacts are committed and drift-gated from a cold build.
7. UI changes are cross-platform by default; narrowing is written down.
8. Adopt the platform: the OS owns the window, selection, IME, accessibility and scrolling; the design system owns what is inside the frame.
9. Keep shells thin so iteration cost stays bounded.
10. Name what you give up.

- [ ] **Step 2: Write §8 Platform-shape decision tree** — seven questions, each with branches and the outcome they imply (**tab web app** / **installed PWA** / **shared core + native shells** / **single-platform native**), each branch naming what it gives up; a closing matrix; a "clearly not this shape" list. Questions: OS targets; is platform feel a product goal; is the product centred on text editing, selection, IME or accessibility; does a server or mobile counterpart need the same logic; team fluency per platform; runway; plugin ecosystem.

- [ ] **Step 3: Write §9 Native-shell ship audit** — thirty to forty one-line items in sections (cold launch, window and focus, input, keyboard, system integration, accessibility, parity), each marked **free** when a native toolkit supplies it by default ("free, still verify").

- [ ] **Step 4: Lint and scan**

Run: `npx --yes markdownlint-cli@0.45.0 standards/architecture/arch-07_cross_platform_shared_core_standards.md`
Expected: clean. Re-read for the confidentiality constraint.

- [ ] **Step 5: Commit**

```bash
git add standards/architecture/arch-07_cross_platform_shared_core_standards.md
git commit -m "feat(arch-07): add tenets, platform-shape decision tree and native-shell audit"
```

### Task 3.2: `arch-11` UI surface standard and catalog row

**Files:**

- Create: `standards/architecture/arch-11_ui_surface_standards.md`
- Modify: `standards/catalog.tsv` (row after `arch-10`), regenerated regions via `make generate-standards-lists`

- [ ] **Step 1: Write `arch-11`** with sections: 1 Scope; 2 Who owns what (three two-column tables: browser tab, installed PWA, native shell); 3 The audit (sections: input and cursor; windowing and focus; materials and visual; scrolling; motion; keyboard; loading and empty states; system integration; accessibility; sixty to eighty one-line items, each tagged `[web]`, `[native]` or `[both]`; include installed-PWA items: window-controls-overlay title bars, standalone display mode, theme-color, `prefers-color-scheme` without flicker); 4 Project rulings beat the audit (describe a rulings ledger: one row per pattern, what it replaced, the assertion that holds it; platform primers: what a pattern becomes per platform and what has gone wrong; admission rule: a primer line enters only by discharging a shipped defect; suggested location `docs/design/`; not mandated); 5 Review usage; 6 Output style for agents (cite item or tenet by number, cite file and section, name what is given up); 7 Sources (attribution: yetone, native-feel-skill, MIT, URL).

Loading policy to state: nothing under 200 ms, spinner 200 ms–2 s, progress beyond; skeletons only where a project ruling says so.

- [ ] **Step 2: Add the catalog row**

`architecture/arch-11_ui_surface_standards.md	UI surface: platform ownership, the native-feel audit, project rulings over audit`

- [ ] **Step 3: Regenerate and check**

Run: `make generate-standards-lists && make check-agent-configs && npx --yes markdownlint-cli@0.45.0 standards/architecture/arch-11_ui_surface_standards.md`
Expected: regions updated in `CLAUDE.md`, `AGENTS.md`, `.gemini/GEMINI.md`, `.github/copilot-instructions.md`, `standards/README.md`, `docs/reference/*.md`; check PASS; lint clean.

- [ ] **Step 4: Commit**

```bash
git add standards/architecture/arch-11_ui_surface_standards.md standards/catalog.tsv CLAUDE.md AGENTS.md .gemini/GEMINI.md .github/copilot-instructions.md standards/README.md docs/reference docs/getting-started
git commit -m "feat(arch-11): add UI surface standard and regenerate standards lists"
```

### Task 3.3: The two profile blocks

**Files:**

- Create: `standards/shared/blocks/profile-shared-core.md`, `standards/shared/blocks/profile-ui-surface.md`

- [ ] **Step 1: Write both blocks**, ten to fifteen lines each, in the voice of `role-app.md` (imperative, one rule per line, no headings). Each block ends with one line citing its standard (`See arch-07 §7–9` / `See arch-11`).

`profile-shared-core.md` carries, one line each: logic is shared and written once, rendering is per platform, a behavior difference between platforms is a bug; the core has no I/O and no ambient state (clock, id minting, locale, timezone are injected); the core exposes a coarse-grained serializable facade and shells never reach past it; conformance is golden vectors replayed through every binding, through the FFI; generated bindings and artifacts are committed and drift-gated from a cold build; a UI change applies to every platform by default and narrowing is written into the issue or PR with the reason; prefer a native shell over a web view when platform feel is a product goal, and record a web view as an interim step in an ADR; every recommendation names what it gives up.

`profile-ui-surface.md` carries, one line each: the platform owns the window, selection, spelling, the context menu, scrolling, focus order and the accessibility tree, and the design system owns what is inside the frame; do not reimplement what the platform draws; no pointer cursor on rows, buttons or tabs; chrome text is not selectable; no smooth-scroll polyfills; no route transitions by default; honor reduced motion; loading shows nothing under 200 ms, a spinner from 200 ms to 2 s, progress beyond, and skeletons only where a project ruling says so; dialogs, sheets, menus, notifications and save panels use the platform primitive where one exists; every actionable element is reachable by keyboard, focus is visible and platform-styled, Escape always does something; where the project keeps design rulings (a ledger, platform primers) the ruling wins and the change cites it; before claiming a UI change is done, walk the `arch-11` audit for the surface it touches.

- [ ] **Step 2: Verify assembly end to end**

Run: `bash scripts/test-profiles.sh` then a manual `scripts/assemble-config.sh claude-code standards/shared/blocks standards/agents/claude-code/base-claude-code.md /tmp/x.md role-app.md profile-shared-core.md profile-ui-surface.md && grep -n '^## Profiles\|^### ' /tmp/x.md`
Expected: tests ✓; `## Profiles` once, `### Shared Core`, `### UI Surface`.

- [ ] **Step 3: Commit**

```bash
git add standards/shared/blocks/profile-shared-core.md standards/shared/blocks/profile-ui-surface.md
git commit -m "feat(blocks): add shared-core and ui-surface profile blocks"
```

### Task 3.4: Profile skills and skill text updates

**Files:**

- Create: `standards/skills/shared-core.md`, `standards/skills/ui-surface.md`
- Modify: `standards/skills/merge-standards.md:73` (add `## Profiles` to the heading list), `standards/skills/setup-wizard.md` (Step 3b: Profiles, after role), `standards/skills/config-assembly.md:53` (profile blocks after role blocks)
- Test: `scripts/test-setup-safe.sh` Test 92 (every `standards/skills/*.md` lands) — gated skills must now be excluded from that expectation when no profile is declared; update the test to assert the two profile skills are absent by default and present with `--profiles`.

**Interfaces:**

- Produces: frontmatter `name: shared-core`, `description: …`, `profiles: shared-core` (and the `ui-surface` pair). Each under 100 lines with sections `## When to Use`, `## Workflow`, `## Output style`.

- [ ] **Step 1: Write the failing test change** in `test-setup-safe.sh` Test 92.

- [ ] **Step 2: Run to verify it fails** — Run: `bash scripts/test-setup-safe.sh`; expected: Test 92 ✗ (gated skills installed by the default run only once they exist; the assertion of absence fails until Step 3 lands the `profiles:` key).

- [ ] **Step 3: Write the two skills.** Frontmatter descriptions (verbatim):

`shared-core`: "Use when adding or changing a platform shell, touching the core↔shell boundary (FFI, WASM, facade types, golden vectors), deciding whether a new feature's logic belongs in the core or a shell, or asking whether a product should be a web app, an installed PWA, or native shells over a shared core. Do NOT use for projects that have not declared the shared-core profile."

`ui-surface`: "Use before changing or reviewing any user-facing UI on web, desktop or mobile, when a UI feels web-y or feels off, before a design pass, before claiming a UI change is done, and when choosing between a platform primitive and a custom one. Do NOT use for projects that have not declared the ui-surface profile."

Workflow sections: `shared-core` reads `arch-07` §7 first, routes the question to the matching `arch-07` section, runs the §8 decision tree before recommending a shape and is willing to conclude the profile does not apply, walks the §9 audit before calling a shell done. `ui-surface` looks for a rulings ledger or platform primers under `docs/design/` (or wherever the project's agent guide points) and finds the row before touching code, reads `arch-11` §2 for the surface class, walks the §3 items for the touched surface before "done", and says so when no ruling and no audit item applies rather than inventing. Output style for both: cite the item or tenet by number, cite the file and section rather than the whole standard, name what each recommendation gives up.

- [ ] **Step 4: Update the three existing skills** as listed.

- [ ] **Step 5: Run to verify**

Run: `bash scripts/test-setup-safe.sh && bash scripts/test-profiles.sh && wc -l standards/skills/shared-core.md standards/skills/ui-surface.md`
Expected: all ✓; both under 100 lines.

- [ ] **Step 6: Commit**

```bash
git add standards/skills scripts/test-setup-safe.sh
git commit -m "feat(skills): add profile-gated shared-core and ui-surface skills"
```

### Task 3.5: `web-tells` check

**Files:**

- Create: `scripts/lint-checks/profiles/ui-surface/web-tells.sh`
- Modify: `scripts/lint-checks/README.md` (a "Profile checks" table: `ui-surface/web-tells`, arch-11, WARN)
- Test: `scripts/test-lint-standards.sh`

**Interfaces:**

- Produces: `CHECK_NAME="web-tells"`; enumerates via `lint_list_files` filtered to `\.(css|scss|tsx|jsx|vue|svelte|ts|js)$`; patterns `cursor:[[:space:]]*pointer`, `scroll-behavior:[[:space:]]*smooth`, `behavior:[[:space:]]*['"]smooth['"]`, `user-select:[[:space:]]*text`; reads `.standards-ui-allow` (one glob per line, `#` comments, converted with `lint__glob_to_ere`); output `PASS web-tells no web tells found` or `WARN web-tells N hit(s): a.css:12, b.tsx:40 (+k more); allowlist: .standards-ui-allow`; exit 0 or 2; never 1.

- [ ] **Step 1: Write the failing tests**

```bash
# Test N: module exists and is executable
# Test N+1: project with src/a.css `cursor: pointer` and src/b.ts `behavior: 'smooth'` → WARN line "2 hit(s)" naming both file:line
# Test N+2: .standards-ui-allow containing "src/a.css" → WARN "1 hit(s)" naming only b.ts
# Test N+3: no matching files → "PASS web-tells"
# Test N+4: seven hits → message lists five and "(+2 more)"
# Test N+5: via lint-standards.sh with profiles: [ui-surface], --format sarif → valid JSON containing "web-tells" with level "warning"
```

- [ ] **Step 2: Run to verify they fail** — Run: `bash scripts/test-lint-standards.sh`; expected: new tests ✗.

- [ ] **Step 3: Implement**, modelled on `scripts/lint-checks/typescript/banned-functions.sh` for the capped file:line message and on `artifact-hygiene.sh` for the library sourcing.

- [ ] **Step 4: Run to verify they pass** — Run: `bash scripts/test-lint-standards.sh && shellcheck scripts/lint-checks/profiles/ui-surface/web-tells.sh`; expected: ✓.

- [ ] **Step 5: Commit**

```bash
git add scripts/lint-checks/profiles scripts/lint-checks/README.md scripts/test-lint-standards.sh
git commit -m "feat(lint): add ui-surface web-tells check"
```

### Task 3.6: Layer gate and changelog

**Files:**

- Modify: `CHANGELOG.md` (extend the profiles entry: the two profiles, `arch-07` §7–9, `arch-11`, the two skills, `web-tells`)

- [ ] **Step 1: Run the full layer gate** (same command as Task 2.8 Step 2).
- [ ] **Step 2: Confidentiality read** of `git diff main...HEAD -- standards/` and `git log main..HEAD --format=%B`.
- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): record the shared-core and ui-surface profiles"
```

---

## Phase 4: Docs layer (`04-docs`)

Start with `gh stack add feat/standards-profiles/04-docs`.

### Task 4.1: Reference and guide documentation

**Files:**

- Modify: `standards/shared/standards-yml-schema.md` (`### profiles` after `### role`: type, valid values table, default, unknown-is-error, example), `templates/standards.yml.example` (the commented stanza from Task 2.5), `docs/guides/customization.md` (new `## Profiles` section before `## Tips`), `docs/getting-started/how-it-works.md` (third selector axis in the assembly explanation), `docs/reference/scripts.md` (`detect-profiles.sh` section; `--profiles` under `setup.sh`, `assemble-skills.sh`, `assemble-config.sh`), `STRUCTURE.md` (`lint-checks/profiles/`, `arch-11`, the two blocks and skills), `README.md` (one Feature Highlights bullet), `standards/process/proc-04_agent_workflow_standards.md` §7 (one line: when `ui-surface` is declared, validation also walks the `arch-11` audit items for the touched surface).

- [ ] **Step 1: Write every change** listed. Examples use a synthetic project name.
- [ ] **Step 2: Verify** — Run: `npx --yes markdownlint-cli@0.45.0 'standards/**/*.md' 'docs/**/*.md' '*.md' --ignore REVIEW.md && ./scripts/lint-standards.sh . && make check-agent-configs`; expected: clean; `doc-lint` PASS (links resolve).
- [ ] **Step 3: Commit**

```bash
git add standards/shared/standards-yml-schema.md templates/standards.yml.example docs STRUCTURE.md README.md standards/process/proc-04_agent_workflow_standards.md
git commit -m "docs: document the profiles selector and the two profiles"
```

### Task 4.2: ADR 0002

**Files:**

- Create: `docs/adr/0002-profiles-as-a-selector-axis.md` from `templates/docs/adr.md`

- [ ] **Step 1: Write it** — Status Accepted; Date 2026-10-22; Related `#227`, the spec path; Context (two selector axes, the gap); Decision (a `profiles` list rather than a value of `architecture` or a `skills` list; fixed list over plugins; one `## Profiles` heading; WARN-level checks in v1); Consequences (opt-in only, no change for existing users, adding a profile is a PR here, FAIL promotion is a later decision).
- [ ] **Step 2: Verify** — Run: `./scripts/lint-checks/common/doc-lint.sh .`; expected: `PASS doc-lint …`.
- [ ] **Step 3: Commit** — `git add docs/adr && git commit -m "docs(adr): record profiles as a selector axis"`

### Task 4.3: Blog post

**Files:**

- Create: `website/src/content/docs/blog/standards-profiles.md` (frontmatter like `ai-agent-skills.md`: title, date 2026-10-22, authors C65 LLC)

- [ ] **Step 1: Write it** — what a profile is and why opt-in; the two profiles with a synthetic example each; the `profiles:` frontmatter key for skills; the `web-tells` check and its allowlist; how to opt in. No private names.
- [ ] **Step 2: Verify** — Run: `cd website && npm ci && npm run build`; expected: build succeeds.
- [ ] **Step 3: Commit** — `git add website/src/content/docs/blog/standards-profiles.md && git commit -m "docs(blog): introduce standards profiles"`

### Task 4.4: Layer gate and final changelog

- [ ] **Step 1: Run the full layer gate** (Task 2.8 Step 2) plus the website build.
- [ ] **Step 2: Confidentiality read** of the whole stack: `git diff main...HEAD` and `git log main..HEAD --format=%B`.
- [ ] **Step 3: Commit** any changelog wording fix: `git commit -m "docs(changelog): finalise the 1.6.0 profiles entry"`.

---

## Execution

1. `gh stack view` shows four layers in order. `gh stack push`, then `gh stack submit --auto`.
2. For every layer: `gh pr edit <n> --title "<title from the PR map>" --body-file <layer-body>.md` using `templates/stacked-pr-description.md.example` (Stack line, Summary, Stands alone because, Depends on / enables, Tested commit SHA with the gate commands and results, Review notes, Checklist, the `🤖 Generated with [Claude Code](https://claude.com/claude-code)` line), then `gh pr ready <n>`.
3. Merge loop per layer, bottom-up (proc-03 §1): wait for the automated reviewer, address every finding by appending commits, all checks green, `gh stack merge --squash --yes <pr>`; after each merge `gh stack sync`.
4. After the last layer merges: `gh stack sync --prune`, remove the worktree, tag `v1.6.0` per `proc-02` §5 once the changelog heading is cut.
