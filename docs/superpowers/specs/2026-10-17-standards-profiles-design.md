# Standards Profiles: `shared-core` and `ui-surface` — Design Spec

**Date:** 2026-10-17
**Status:** Draft
**Goal:** Let a project opt in to cross-cutting standards that do not follow from its
languages or role, starting with two profiles: `shared-core` (one shared logic core, thin
native shells) and `ui-surface` (what makes a UI feel like it belongs on its platform). Fix
Claude Code skill installation so that opted-in skills actually load.

---

## Problem Statement

`.standards.yml` selects content along two axes: `languages` (one block per language) and
`role` (one block for `service`, `library`, `app` or `data-pipeline`). Everything else in
the standards tree is either injected for every project (`architecture-core.md`,
`testing-policy.md`, …) or never injected at all.

Three things fall through that gap:

1. **Cross-cutting standards with no selector.** `arch-07` (Cross-Platform Shared-Core
   Standards) applies to a specific product shape: one logic core, several native shells.
   It is documented but reaches no agent config, because nothing in `.standards.yml` can
   say "this project has that shape." A pure web service and a five-platform suite get the
   same assembled `CLAUDE.md`.

2. **Platform-feel knowledge has no home at all.** Whether a UI reads as "a web page in a
   frame" or "an app on this platform" is decided by a few dozen cheap, checkable details:
   cursor changes on hover, selectable chrome text, smooth-scroll polyfills, route fades,
   custom window shadows, modal overlays instead of native sheets. The standards tree says
   nothing about them. Projects that have learned these lessons keep them in private
   design docs; projects that have not repeat the mistakes.

3. **Claude Code skills do not load.** `setup.sh` and `sync-standards.sh` copy
   `merge-standards.md` to `.claude/skills/merge-standards.md` as a flat file. Claude Code
   discovers project skills at `.claude/skills/<name>/SKILL.md`. In a project set up by
   this repo, the skill file is present on disk and absent from the agent's skill list.
   The other seven skills under `standards/agents/claude-code/skills/` are never copied
   anywhere. Any new skill this spec adds would inherit the same fate unless the install
   path is fixed first.

### Prior art

[yetone/native-feel-skill](https://github.com/yetone/native-feel-skill) (MIT) is an agent
skill for cross-platform desktop apps. It was reviewed as a candidate for direct adoption
and rejected, for two reasons that shape this design:

- **Its architecture contradicts `arch-07`.** It places the cross-platform seam at the
  rendering surface: one React UI in the system WebView, a native shell below it. `arch-07`
  places the seam below the UI: one logic core, hand-written native rendering per platform.
  Both are coherent. They are opposite answers, and the skill's trigger words ("Tauri vs
  native", "WKWebView", "cross-platform desktop") would fire inside projects that have
  chosen `arch-07` and argue against their recorded decisions.
- **Its checklists are the useful part.** Its native-conventions audit and ship-readiness
  list are platform-agnostic, cheap to check, and mostly right. They are the source
  material for the `ui-surface` profile, rewritten in this repo's voice and reconciled
  with `arch-07` (for example, it forbids loading skeletons under 500 ms; a project may
  rule otherwise, and a cited project ruling wins).

The one-paragraph summary of its stance, and the eight-tenet shape of its philosophy
file, are worth borrowing as a **form**. The content is inverted.

---

## Goals

- A project can declare `profiles: [shared-core, ui-surface]` (either, both, or neither)
  in `.standards.yml` and get the matching block in every assembled agent config, the
  matching Claude Code skill installed, and the matching lint checks run.
- Nothing changes for a project that declares no profiles. The key is optional, the
  default is empty, and no profile is ever enabled by auto-detection.
- A project with a UI but no shared core (a single-platform web app, an installed PWA)
  can take `ui-surface` alone.
- Claude Code skills install in the directory form Claude Code discovers, for the
  always-on `merge-standards` skill and for profile skills alike.
- Everything added is publishable under this repo's MIT license with no reference to any
  private repository, product, issue tracker or design document.

## Non-goals

- Installing the six remaining skills (`standards-audit`, `security-gate`, …) by default.
  They move to directory form in this change so they *can* be installed; whether they
  should be is a separate decision.
- A general plugin system. Profiles are a fixed, documented list in this repo, like
  languages and roles. Adding one is a PR here.
- Per-profile configuration (thresholds, allowlists) in `.standards.yml`. v1 profiles are
  booleans by presence.
- Onboarding the author's own projects. That happens per project after release, and the
  per-project PRs are not part of this spec.

## Anti-goals

- **Any profile enabled without the project saying so.** Detection may *suggest*; only the
  committed `.standards.yml` *declares*.
- **A `ui-surface` audit that fights a project's own design rulings.** Where a project has
  a rulings ledger or platform primers, those win and the audit says so.
- **Leaking private material.** Not product names, not repository paths, not issue or
  defect identifiers, not quoted rulings. See [Confidentiality](#5-confidentiality).

---

## Design Decisions

- **New top-level key `profiles`**, a list, optional, default empty. It is the third
  selector axis beside `languages` and `role`, and it uses the same block-naming and
  assembly path (`standards/shared/blocks/profile-<name>.md`).
- **Two profiles ship in v1:** `shared-core` and `ui-surface`. They are independent.
- **`shared-core` extends `arch-07`** rather than adding a new standard. `arch-07` is
  already the right document; it gains a tenets section, a platform-shape decision tree
  and a native-shell ship audit, and the profile is what injects a block citing it.
- **`ui-surface` adds one new standard**, `arch-11_ui_surface_standards.md` (the number
  follows `arch-09` and `arch-10`, both claimed by open PRs at the time of writing; the
  builder renumbers if those PRs land differently).
- **Profile skills are routing skills, under 100 lines.** They name triggers, point at the
  standard and its checklists, and set the output style. They do not restate the audit.
- **Skill install is generalized** to "copy `skills/<name>/SKILL.md` to
  `.claude/skills/<name>/SKILL.md`", gated on `claude-code` being in `agents`, with a
  one-time migration away from the flat file.
- **Lint checks for a profile are WARN-level in v1.** The `ui-surface` web-tells check
  reports; it does not block. Promoting it to FAIL is a later decision once projects have
  seen the output. *(Author's call; the alternative was a hard gate from day one.)*
- **Schema version stays `1`.** The key is additive and optional.
- **Release as a minor version** (`1.6.0`), with a changelog entry and a blog post.

---

## 1. The `profiles` key

### Schema

```yaml
# .standards.yml
version: 1
languages: [typescript, rust, swift]
agents: [claude-code, codex]
role: app
profiles:            # optional; default: none
  - shared-core
  - ui-surface
```

| Value | Block | Standard | Skill | Lint checks |
|-------|-------|----------|-------|-------------|
| `shared-core` | `profile-shared-core.md` | `arch-07` (extended) | `shared-core` | none in v1 |
| `ui-surface` | `profile-ui-surface.md` | `arch-11` (new) | `ui-surface` | `lint-checks/profiles/ui-surface/*.sh` |

Both inline (`profiles: [a, b]`) and block list forms parse, via the existing `yaml_list`.

### Validation

- An unknown profile name is an error at setup and sync time, with the valid list printed.
  This matches how an unknown agent is handled, and it is stricter than languages because
  a typo here silently drops a whole standard.
- Duplicates are collapsed. Order in the file is the order blocks are appended.

### Assembly

`sync-standards.sh` and `diff-standards.sh` build their block list as: language blocks,
then the role block, then profile blocks in declared order. Both go through the same
mapping helper today and both must learn profiles; the diff script is easy to forget.
Profile blocks appear in every agent's assembled config, not only Claude's, because the
block is the cross-agent form of the profile.

`assemble-config.sh` learns the `profile-` prefix. Today it recognizes `lang-` and `role-`
and appends any other block under a warning with no heading. Profile blocks render as one
`## Profiles` section with a `### <Profile Name>` sub-heading per block, mirroring
`## Language Standards`, and `derive_name` strips `profile-` the way it strips the other
two prefixes. The `merge-standards` skill keys its merge strategy on the fixed list of
`##` headings, so `## Profiles` is added to that list in the same change. *(Author's call;
the alternative was one `##` per profile, which would grow the heading list with every
profile added.)*

The generated agent-config lists (an open PR adds a generator and a drift gate) enumerate
standards documents, not blocks. `arch-11` is picked up by its catalog row; no new region
type is added for profiles. *(Author's call.)*

### `setup.sh`

- New flag `--profiles <a,b>`; absent means none. Unknown values are rejected the same way
  unknown flags are in the open setup-hardening PR.
- The setup wizard skill (`setup-wizard`) asks about profiles after role, with a one-line
  description of each and the suggestion from detection (below), phrased as a question.

### Detection and `doctor`

`scripts/detect-profiles.sh` prints *suggestions*, one per line, from cheap heuristics:

| Suggest | When |
|---------|------|
| `shared-core` | a `Cargo.toml` depends on `uniffi` or `wasm-bindgen`, or the tree has both a `crates/` (or `core/`) directory and more than one of `shells/`, `apps/`, `ios/`, `android/`, `windows/`, `macos/` |
| `ui-surface` | a web app manifest (`manifest.json` / `manifest.webmanifest`) exists, or `role: app`, or any Swift, Kotlin, Dart or C# UI framework import is found |

`doctor.sh` gains `check_profiles`:

- unknown declared profile → **fail** (it would have been rejected at sync; say so);
- declared profile whose skill directory is missing while `claude-code` is an agent →
  **warn**, "run `make sync-standards`";
- suggested but not declared → **pass** with an informational hint. Not a warn: the whole
  point of a profile is that opting out is normal.

---

## 2. Profile content

### 2.1 `shared-core`

**Block** `standards/shared/blocks/profile-shared-core.md`, ten to fifteen lines in the
voice of `role-app.md`. The builder writes it from these points:

- Logic is shared and written once; rendering is per platform. A behavior difference
  between platforms is a bug.
- The core has no I/O and no ambient state. Clock, id minting, locale and timezone are
  injected.
- The core exposes a coarse-grained, serializable facade. Shells never reach past it.
- Conformance is golden vectors, replayed through every binding, through the FFI, not
  beside it.
- Generated bindings and artifacts are committed and drift-gated from a cold build.
- A UI change applies to every platform by default. Narrowing is written into the issue or
  PR with the reason.
- Prefer a native shell over a web view when platform feel is a product goal; a web view
  is an interim step recorded in an ADR, never a silent destination.
- Every recommendation names what it gives up.

**Standard: `arch-07` gains three sections.**

*Tenets.* Eight to ten numbered tenets, each one tension and one structural answer, so an
agent can cite "T3 — inject ambient inputs" the way it cites a lint rule. The list above
is the source. The builder keeps each under four sentences.

*Platform-shape decision tree.* Seven questions, modelled on the prior art's tree but
answering a different question: *which shape should this product take?* Outcomes are
**tab web app**, **installed PWA**, **shared core + native shells**, or **single-platform
native**. Questions cover: number of OS targets; whether platform feel is a product goal
or a nicety; whether the product centers on text editing, selection, IME or accessibility
(these are where web surfaces are weakest and native shells are strongest); whether a
server or mobile counterpart needs the same logic; team fluency per platform; runway.
Each branch states what it gives up. The tree must be able to answer "don't use
`shared-core`"; a tree that always recommends its own profile is not a tree.

*Native-shell ship audit.* The native half of the audit in §2.2, as a checklist the
builder can keep in one place and cite from `arch-11`. Items that a native toolkit gives
for free (window chrome, overlay scrollbars, focus rings) stay on the list, marked "free,
still verify," because refactors silently undo them.

**Skill** `standards/agents/claude-code/skills/shared-core/SKILL.md`:

```yaml
name: shared-core
description: Use when adding or changing a platform shell, touching the core↔shell
  boundary (FFI, WASM, facade types, golden vectors), deciding whether a new feature's
  logic belongs in the core or a shell, or asking whether a product should be a web app,
  an installed PWA, or native shells over a shared core. Do NOT use for projects that have
  not declared the shared-core profile.
```

Body: read `arch-07` §1 tenets first; route the question to the matching `arch-07`
section; before recommending a platform shape run the decision tree and be willing to
conclude the profile does not apply; before claiming a shell is done walk the native-shell
audit; always name the trade-off.

**Lint:** none in v1. The drift gate for committed artifacts is being added by an open PR
under `arch-07` §3 and is not profile-specific.

### 2.2 `ui-surface`

**Block** `standards/shared/blocks/profile-ui-surface.md`, the same length, from these
points:

- The platform owns the window, selection, spelling, the context menu, scrolling, focus
  order and the accessibility tree. The design system owns what is inside the frame.
  Do not reimplement what the platform draws.
- No pointer-cursor on rows, buttons or tabs; chrome text is not selectable; no
  smooth-scroll polyfills; no route transitions by default; honor reduced motion.
- Loading: nothing under 200 ms, a spinner from 200 ms to 2 s, progress beyond. Skeleton
  placeholders only where a project ruling says so.
- Dialogs, sheets, menus, notifications and save panels are the platform's where a
  platform primitive exists.
- Every actionable element is reachable by keyboard; focus is visible and platform-styled;
  Escape always does something.
- Where the project keeps design rulings (a ledger, platform primers), the ruling wins
  over this list and the change cites it.
- Before claiming a UI change is done, walk the audit for the surface it touches.

**Standard** `standards/architecture/arch-11_ui_surface_standards.md`:

1. *Scope.* Applies to any project that ships a UI to users on a desktop or mobile
   platform, including web apps installed as PWAs. Independent of `shared-core`.
2. *Who owns what.* A two-column table per surface class (web in a browser tab, installed
   PWA, native shell): what the platform owns, what the design system owns. This is the
   section that stops an agent from drawing its own scrollbar.
3. *The audit.* Sections: input and cursor; windowing and focus; materials and visual;
   scrolling; motion; keyboard; loading and empty states; system integration;
   accessibility. Every item is tagged **[web]**, **[native]** or **[both]**, is one line,
   and is observable without reading source where possible. Target sixty to eighty items.
   The prior art's lists are the source; the builder rewrites each item rather than
   copying, drops WebView-host-specific items (occlusion flags, presentation-update hooks)
   that assume the rejected architecture, and adds the installed-PWA items the prior art
   lacks (window controls overlay title bars, standalone display mode, theme-color,
   `prefers-color-scheme` without flicker).
4. *Project rulings beat the audit.* The convention: a project may keep a **rulings
   ledger** (one row per UI pattern, with what it replaced and the assertion that holds it)
   and **platform primers** (what a pattern becomes on each platform, and what has gone
   wrong there). The standard describes the shape and the admission rule (a primer line
   enters only by discharging a shipped defect), names the suggested location
   (`docs/design/`), and states that a cited ruling overrides any audit item. It does not
   mandate the files.
5. *Review usage.* For a PR touching UI, pick the five to ten audit items in its surface
   area and check them explicitly. For a "feels off" report, walk the list with the
   reporter. For a refactor, walk the whole list.
6. *Output style for agents.* Cite the audit item or tenet by number; cite the file and
   section, not the whole standard; name what each recommendation gives up.
7. *Sources.* Attribution to the prior art by name and license, as required by MIT when
   material is adapted.

**Skill** `standards/agents/claude-code/skills/ui-surface/SKILL.md`:

```yaml
name: ui-surface
description: Use before changing or reviewing any user-facing UI on web, desktop or
  mobile, when a UI "feels web-y" or "feels off", before a design pass, before claiming a
  UI change is done, and when choosing between a platform primitive and a custom one.
  Do NOT use for projects that have not declared the ui-surface profile.
```

Body: if the project has a rulings ledger or platform primers under `docs/design/` (or
wherever its agent guide points), find the row before touching code and cite it; read
`arch-11` §2 for the surface class; before "done", walk the audit items for the touched
surface; cite by number; name the trade-off; if there is no ruling and the audit is
silent, say so instead of inventing.

**Lint** `scripts/lint-checks/profiles/ui-surface/web-tells.sh`, WARN-level, runs only when
the profile is declared, over files `lint-standards.sh` already enumerates:

| Pattern | Files |
|---------|-------|
| `cursor: pointer` | `.css`, `.scss`, `.tsx`, `.jsx`, `.vue`, `.svelte` |
| `scroll-behavior: smooth` and `behavior: 'smooth'` | same, plus `.ts`, `.js` |
| `user-select: text` | same |

The check follows the runner's existing one-line-per-check protocol: one `WARN` line
with the hit count and up to five `file:line` locations in the message text, the way the
TypeScript banned-functions check reports. Per-finding SARIF locations are out of scope;
the runner's SARIF emitter and the review action's formatter keep their current contract.
*(Author's call; real per-result locations would change the JSON and SARIF schemas every
consumer of the action depends on, and that is a separate change if wanted.)*

The check reads an optional allowlist file, `.standards-ui-allow`, one glob per line, so
a project can record "these are deliberate" without silencing the whole check. The
allowlist is committed, which is the point: a ruled exception is written down. No path
heuristic classifies editor or content directories in v1: `user-select: text` is reported
wherever it appears and the allowlist is the only exemption. It is rare in practice and a
deterministic rule beats a guessable one. *(Author's call.)*

`lint-standards.sh` learns a third loop: after common and language checks, for each
declared profile run `lint-checks/profiles/<profile>/*.sh` if the directory exists.

---

## 3. Skill installation

### Directory form

Every skill under `standards/agents/claude-code/skills/` moves from `<name>.md` to
`<name>/SKILL.md`. Frontmatter is unchanged. The blog post and docs that describe skills
as "markdown files in that directory" are updated to say directories.

### Install and sync

A shared function in `scripts/lib/` (the builder picks the file; `assembly.sh` is the
natural home):

```text
install_claude_skill <name> <standards-dir> <project-root> <dry-run>
```

- Installs `skills/<name>/SKILL.md` as `.claude/skills/<name>/SKILL.md`, creating the
  directory, **checksum-guarded the same way agent configs are**: the installed file's
  hash is recorded in `.standards-checksums`; on sync, a file whose hash still matches is
  overwritten with the new version, and a file whose hash differs is left alone while the
  new version is written to `.standards-pending/` for `merge-standards` to resolve. A
  pre-existing file with no recorded hash is treated as customized: left, staged to
  pending, warned about. Prints the same `[dry-run] Would …` lines the rest of the scripts
  print. *(Author's call. The earlier draft said "copy when different," which would
  clobber local edits; nothing else this repo installs does that, and the removal rule
  below already assumed edits happen.)*
- Only runs when `claude-code` is in the **effective agent list used for assembly**, the
  same resolved list `doctor` reads. This is the list after `--agents`, `.standards.yml`
  and detection have been reconciled, not the raw request. The open setup-hardening PR
  gates `merge-standards` on the requested list, which can be true with no Claude config
  present; this change aligns that gate to the effective list, in the skill-install PR,
  since that PR touches the `merge-standards` install anyway. *(Author's call.)*
- The always-installed set is `merge-standards`. The profile set is one skill per declared
  profile, same name as the profile.
- **Migration:** if `.claude/skills/merge-standards.md` (the flat file) exists, remove it
  after the directory form is written, and print one line saying why.
- **Removal:** when a profile is no longer declared and the installed skill's hash still
  matches `.standards-checksums`, remove it, drop the checksum entry and print a line. If
  it differs, leave it and warn that it is no longer managed. The same guard serves both
  directions.
- `make doctor` reports a declared profile whose skill directory is missing (above).

### Other agents

Skills are a Claude Code mechanism. For Cursor, Copilot, Gemini, Codex and Aider the
profile block in the assembled config is the whole delivery, and `arch-07` / `arch-11`
are the reference. No per-agent prompt documents are added for profiles; the blocks are
short enough to carry the rule and the standards carry the detail. *(Author's call.
`merge-standards` has a prompt document because it is a multi-step procedure; a profile
is not.)*

---

## 4. Documentation

Everything below is in scope for the same release. The website syncs `docs/` and
`standards/` automatically; no website-specific pages are needed beyond the blog post.

| Document | Change |
|----------|--------|
| `standards/shared/standards-yml-schema.md` | `profiles` field: type, valid values, default, example; the "unknown value is an error" rule |
| `templates/standards.yml.example` | commented `profiles:` stanza with both values described in one line each |
| `docs/guides/customization.md` | a "Profiles" section: what they are, how to opt in, how they differ from role, how to remove one |
| `docs/getting-started/how-it-works.md` | the third selector axis in the assembly explanation |
| `docs/reference/scripts.md` | `detect-profiles.sh`; `setup.sh --profiles`; the skill install function |
| `docs/reference/agent-configs.md` | describes the Claude and Codex mechanisms as `.aiderrc` / `.codexrc`; correct it to `.claude/skills/<name>/SKILL.md` and `AGENTS.md` while in the file |
| `docs/reference/makefile-targets.md` | only if a new target is added (none planned) |
| `scripts/lint-checks/README.md` | the `profiles/` directory and the WARN-only policy |
| `standards/agents/claude-code/base-claude-code.md` | no change expected; verify the assembled output reads well with a profile block after the role block |
| `standards/architecture/arch-07_…` | the three new sections (§2.1) |
| `standards/architecture/arch-11_…` | new (§2.2) |
| `STRUCTURE.md` | skills as directories; `lint-checks/profiles/`; `arch-11` |
| `README.md` | one bullet under Feature Highlights; the skills sentence under "What You Get" |
| `CHANGELOG.md` | `[Unreleased]` → Added: profiles, two profiles, skill install fix; Changed: skills are directories; Fixed: skills now load |
| `website/src/content/docs/blog/` | one post: what a profile is, why opt-in, the skill install fix, with the two profiles as examples. Written last, from the shipped behavior |
| `docs/adr/` | one ADR: "Profiles as a third selector axis" — why not overload `architecture`, why not a `skills` list, why fixed list over plugins |
| `standards/process/proc-04_…` §7 | one cross-reference line: UI change validation now also points at the `ui-surface` audit when the profile is declared |

Review checklist for the docs: every example uses a synthetic project name; every path is
one this repo defines; no document names an external product as an example of either
profile.

---

## 5. Confidentiality

This repository is public under MIT. The profiles are distilled from experience in
private repositories, and the distillation is where leaks happen. Rules for every file
this change touches, and for the builder's commit messages and PR text:

- **No product, company or private-repository names**, including codenames, suite names,
  app names and design-system names. "A five-app suite" is fine. Its name is not.
- **No private paths, issue numbers, PR numbers, defect identifiers or ADR numbers** from
  any repository other than this one.
- **No quoted rulings.** A pattern may be described ("a reserved empty row at the end of a
  list that accepts typing"); a ruling's text, its assertion names and its history may
  not.
- **Examples are synthetic.** Where a standard needs a worked example, it is invented for
  the standard and says nothing true about any real project.
- **Attribution goes to public sources only.** The prior art is public and is cited.
  Lessons from private work are stated as rules, without provenance.
- **The commit history is part of the publication.** A fact scrubbed from the final file
  but present in an earlier commit on the branch is still published. The builder writes
  the files clean from the start rather than cleaning them up later; if a slip is
  noticed before the PR opens, the branch is rewritten.

*Mechanism (author's call, optional for v1):* a CI job in this repo greps the tree, the
commit messages on the PR and the PR body against a regular expression held in a
repository secret, and fails on any match. The secret holds the private terms, so the
denylist itself is never committed. It is a backstop, not the control; the control is the
rules above and the review checklist in §4.

---

## 6. Testing

Functional tests follow `scripts/test-setup-safe.sh`: a temp project per test, run the
script, assert outcomes. A new `scripts/test-profiles.sh`, wired into `make test`:

- `profiles` parses in inline and block form; absent means none.
- unknown profile fails setup and sync with the valid list in the message.
- one profile → its block is in every assembled agent config, after the role block; the
  other profile's block is absent.
- `claude-code` agent + profile → `.claude/skills/<profile>/SKILL.md` exists; without the
  agent it does not; without the profile it does not.
- `merge-standards` installs as `.claude/skills/merge-standards/SKILL.md`; a pre-existing
  flat file is removed and the removal is printed.
- un-declaring a profile removes an unmodified skill directory and leaves a modified one
  with a warning.
- `--dry-run` prints every would-write and would-remove line and changes nothing.
- `doctor` reports each `check_profiles` outcome.
- `lint-standards.sh` runs the `ui-surface` check only when declared; WARN output is well
  formed in text, JSON and SARIF; the allowlist suppresses a matching path.
- `detect-profiles.sh` suggests each profile from a minimal fixture and nothing from an
  empty project.
- `shellcheck` and `bash -n` on every touched script, as the existing tests do.

The assembled-config drift gate from the open generator PR, once merged, covers the
generated lists.

---

## 7. Rollout

1. This spec lands as a docs PR.
2. **Two implementation PRs.** PR A is the skill-install fix (§3): directory form,
   guarded install, migration, the agent-list gate. It depends on nothing open and fixes a
   live defect, so it targets `main` now. PR B is profiles (§1, §2, §4, §6). It uses the
   file enumeration helper, the usage-error style and the generator that three open PRs
   introduce, so it waits for those to merge and then targets `main`; it does not stack on
   unmerged branches. See Open questions for the one decision this leaves.
3. Release `1.6.0`.
4. Projects opt in individually, each in its own PR in its own repository, by adding
   `profiles:` and running `make sync-standards`. Those PRs are outside this spec.

---

## 8. Left to the builder

- Exact wording of the two blocks, the tenets, the decision tree and the audit items, within
  the constraints above.
- Whether `install_claude_skill` lives in `assembly.sh` or a new `skills.sh`.
- The detection heuristics' exact file patterns.
- Whether the skill-install fix ships as its own PR.
- Test fixture layout.

## 9. Open questions

The builder check raised seven questions. Six were settled in place and are marked
*(Author's call)* where they landed: section heading shape, lint output protocol, skill
install guarding, which agent list gates skills, generated-list scope, and `user-select`
classification. One remains for the owner:

1. **Sequencing of PR B against the open PRs.** PR B is written to use the file
   enumeration helper, the setup usage-error style and the list generator that three open
   PRs introduce. If those PRs will merge soon, PR B waits and targets `main` after them.
   If any of them is likely to stall, PR B should instead be built on `main` with its own
   minimal copies of those helpers and reconciled afterward. The spec assumes the first.
   The answer changes the builder's plan, not the design.

---

## Sources

- yetone, *native-feel-skill*, MIT, <https://github.com/yetone/native-feel-skill> — the
  form of the tenets file and the source lists for the `ui-surface` audit. The
  architecture it recommends is not adopted; see Prior art.
- This repo: `arch-05` §2–3 (pure render logic, semantic layout state), `arch-07`
  (shared core), `proc-04` §7 (UI change validation), `role-app.md`.
