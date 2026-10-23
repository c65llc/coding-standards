# Standards Profiles — Design Spec

- **Status:** Agreed
- **Date:** 2026-10-22 (first draft 2026-10-17, revised against `main` after the
  agent-neutral skills change landed)
- **Related:** ADR 0002, `docs/superpowers/plans/2026-10-22-standards-profiles-plan.md`

A spec answers *what* and *why*; the plan answers *how* and *in what order*.

## Purpose

`.standards.yml` selects content along two axes: `languages` (one block per language)
and `role` (one block for `service`, `library`, `app` or `data-pipeline`). Everything
else in the standards tree is either injected for every project or never injected at
all. Two bodies of knowledge fall through that gap:

- **Cross-platform shared-core standards.** `arch-07` applies to one product shape, a
  shared logic core under thin native shells. It is documented but reaches no agent
  config, because nothing in `.standards.yml` can say "this project has that shape."
- **Platform-feel conventions.** Whether a UI reads as "a web page in a frame" or "an
  app on this platform" turns on a few dozen cheap, checkable details: cursor changes on
  hover, selectable chrome text, smooth-scroll polyfills, route fades, custom window
  shadows, modal overlays instead of native sheets. The standards tree says nothing
  about them, so projects that have learned the lessons keep them privately and projects
  that have not repeat the mistakes.

Both are opt-in by nature: a pure web service wants neither, a single-platform web app
wants only the second, a multi-platform suite wants both. This spec adds a third
selector axis, `profiles`, and two profiles.

**Prior art.** [yetone/native-feel-skill](https://github.com/yetone/native-feel-skill)
(MIT) is an agent skill for cross-platform desktop apps. It was reviewed for direct
adoption and rejected: it places the cross-platform seam at the rendering surface (one
React UI in the system WebView, native shell below), which is the opposite of
`arch-07`'s seam below the UI, and its trigger words would fire inside `arch-07`
projects and argue against their recorded decisions. Its native-conventions audit and
ship-readiness list are the useful part and are the source material for the
`ui-surface` profile, rewritten in this repo's voice. The form of its eight-tenet
philosophy file is borrowed; the content is inverted.

## Success

- [ ] A project can declare `profiles: [shared-core, ui-surface]`, either, both or
      neither, and `make sync-standards` puts the matching block in every assembled
      agent config under a `## Profiles` heading, after the role block.
- [ ] A skill under `standards/skills/` can declare which profiles it belongs to, and
      `assemble-skills.sh` installs it only when one of them is declared. Un-declaring a
      profile removes an unmodified installed copy and leaves a modified one with a
      warning. Agents that read one config file see only declared-profile skills in
      their `## Skills` index.
- [ ] A project that declares no profiles is byte-for-byte unaffected: no new block, no
      new skill, no new lint check, no new doctor finding above INFO.
- [ ] An unknown profile name fails `setup.sh` and `sync-standards.sh` with the valid
      list in the message, the way an unknown agent does.
- [ ] `doctor` reports a declared profile with no installed skill as WARN, an unknown
      profile as FAIL, and a detected-but-undeclared profile as INFO.
- [ ] `lint-standards.sh` runs `lint-checks/profiles/<profile>/*.sh` for each declared
      profile, in text, JSON and SARIF, and runs nothing from that directory otherwise.
- [ ] `arch-07` carries numbered tenets, a platform-shape decision tree and a
      native-shell audit; `arch-11` exists with a "who owns what" table per surface
      class, a tagged audit of sixty to eighty items, and the rule that a project's own
      design rulings override the audit.
- [ ] Every document in the plan's documentation table is updated, `make
      check-agent-configs` and `make test` pass, and the changelog carries the entry.
- [ ] No file, commit message or PR body added by this work names a private product,
      repository, issue, defect or ruling.

## Non-goals

- Installing the six skills that are not profile-bound by any new rule. They already
  install everywhere the skill assembler runs; this spec does not change that.
- A general plugin system. Profiles are a fixed, documented list in this repo, like
  languages and roles. Adding one is a PR here.
- Per-profile configuration (thresholds, path classifiers) in `.standards.yml`. v1
  profiles are booleans by presence; the `ui-surface` check's allowlist is a file.
- Per-finding SARIF locations. The lint runner's one-line-per-check protocol and the
  review action's formatter keep their contract; a profile check reports like the
  TypeScript banned-functions check does.
- Onboarding the author's own projects. That is one PR per project after release.

## Anti-goals

- **A profile enabled without the project saying so.** Detection may suggest; only the
  committed `.standards.yml` declares.
- **A `ui-surface` audit that fights a project's own design rulings.** Where a project
  keeps a rulings ledger or platform primers, those win and the audit says so.
- **Leaking private material.** No product, company or private-repository names; no
  private paths, issue, PR, defect or ADR identifiers; no quoted rulings; synthetic
  examples only; attribution to public sources only. The commit history is part of the
  publication, so files are written clean from the start and a slip found before a PR
  opens is rewritten out of the branch.
- **A change to the assembled output of any project that has not opted in.**

## Architecture

```text
.standards.yml ─ profiles: [a, b]
      │
      ├─ sync / setup / diff ─▶ map_profiles_to_blocks ─▶ assemble-config.sh
      │                                                   └─ "## Profiles" / "### <Name>"
      ├─ setup / sync ────────▶ assemble-skills.sh --profiles "a b"
      │                          └─ installs skills whose `profiles:` intersects;
      │                             removes unmodified copies that no longer do
      ├─ lint-standards.sh ───▶ lint-checks/profiles/<a>/*.sh, …/<b>/*.sh
      └─ doctor.sh ───────────▶ check_profiles (+ detect-profiles.sh suggestions)
```

Everything is Infrastructure in this repo's terms: shell scripts, content files and
their tests. There is no domain layer.

**New**

- `standards/shared/blocks/profile-shared-core.md`, `profile-ui-surface.md` — the
  injected blocks, ten to fifteen lines each in the voice of `role-app.md`.
- `standards/architecture/arch-11_ui_surface_standards.md` — scope; who owns what per
  surface class (browser tab, installed PWA, native shell); the audit, each item tagged
  `[web]`, `[native]` or `[both]`; rulings-beat-the-audit; review usage; agent output
  style; sources.
- `standards/skills/shared-core.md`, `standards/skills/ui-surface.md` — routing skills
  under 100 lines with a `profiles:` frontmatter key naming their profile.
- `scripts/lint-checks/profiles/ui-surface/web-tells.sh` — WARN-level; patterns
  `cursor: pointer`, `scroll-behavior: smooth`, `behavior: 'smooth'`, `user-select:
  text` over the runner's enumerated `.css .scss .tsx .jsx .vue .svelte .ts .js`
  files; one line with the hit count and up to five `file:line` locations; honors an
  optional committed `.standards-ui-allow` (one glob per line). No path heuristic for
  editor or content directories: the allowlist is the only exemption.
- `scripts/detect-profiles.sh` — prints suggestions, one per line. `shared-core` when a
  `Cargo.toml` depends on `uniffi` or `wasm-bindgen`, or a `crates/` or `core/` directory
  coexists with more than one of `shells/`, `apps/`, `ios/`, `android/`, `windows/`,
  `macos/`. `ui-surface` when a web app manifest exists, `role: app` is declared, or a
  Swift, Kotlin, Dart or C# UI-framework import is found.
- `scripts/test-profiles.sh` — functional tests, wired into `make test` and CI.
- `docs/adr/0002-profiles-as-a-selector-axis.md`.

**Changed**

- `scripts/lib/checksums.sh` — `read_standards_config` sets `STD_PROFILES` from
  `yaml_list`.
- `scripts/lib/languages.sh` — `KNOWN_PROFILES`, `profile_supported`,
  `map_profiles_to_blocks` beside their language counterparts.
- `scripts/sync-standards.sh`, `scripts/diff-standards.sh`, `scripts/setup.sh` —
  validate profiles (unknown is a usage error with the valid list), append profile
  blocks after the role block in declared order, pass `--profiles` to the skill and
  config assemblers; `setup.sh` gains `--profiles <a,b>` and writes a `profiles:`
  stanza (or a commented one) to `.standards.yml`.
- `scripts/assemble-config.sh` — learns the `profile-` prefix: one `## Profiles`
  section, a `### <Profile Name>` sub-heading per block, `derive_name` strips the
  prefix; takes `--profiles` and filters the `## Skills` index for index-only agents.
- `scripts/assemble-skills.sh`, `scripts/lib/skills.sh` — `--profiles`; `skill_field
  profiles` read as a space- or comma-separated list; a skill with no `profiles:` is
  unconditional; removal of a no-longer-declared skill when ownership is `ours`, with a
  warning when `customized`.
- `scripts/lint-standards.sh` — a third loop after common and language checks, per
  member, over `lint-checks/profiles/<declared>/`.
- `scripts/doctor.sh` — `check_profiles` after `check_languages`.
- `standards/architecture/arch-07_…` — three sections: tenets, platform-shape decision
  tree, native-shell ship audit.
- `standards/skills/merge-standards.md` — `## Profiles` added to the fixed heading list
  its merge strategy keys on. `setup-wizard.md` — a profiles step after role.
  `config-assembly.md` — profile blocks in the block order.
- `standards/catalog.tsv` — a row for `arch-11`; generated regions regenerated.
- Documentation: schema reference, `templates/standards.yml.example`,
  `docs/guides/customization.md`, `docs/getting-started/how-it-works.md`,
  `docs/reference/scripts.md`, `scripts/lint-checks/README.md`, `STRUCTURE.md`,
  `README.md`, `CHANGELOG.md`, `proc-04` §7 cross-reference, one blog post.

**Unchanged but relied on**

- `assemble_agent_config_guarded` and the checksum and pending-dir mechanism: profile
  blocks change assembled content, so a customized config is staged, not overwritten.
- The skill assembler's ownership model (`ours` / `customized` / `foreign`) and its
  `.standards-checksums` entries: profile removal reuses it rather than adding a second
  notion of ownership.
- `lint_list_files` and the runner's `PASS|WARN|FAIL <name> <message>` protocol.
- `generate-standards-lists.sh`: a new standards document is picked up by its catalog
  row; no new region type.

### Decisions worth naming

- **A `profiles` list, not a value of `architecture`.** `architecture` is an
  enforcement level; a project can be `clean` with or without a shared core.
- **One `## Profiles` heading** with sub-headings, mirroring `## Language Standards`,
  so the merge-standards heading list grows by one entry rather than one per profile.
- **`shared-core` extends `arch-07`** instead of adding a standard; `ui-surface` adds
  `arch-11` because nothing existing covers it.
- **Profile skills are routing skills.** They name triggers, point at the standard and
  its checklists, and require naming what each recommendation gives up. They do not
  restate the audit.
- **Profile lint checks are WARN in v1.** Promotion to FAIL is a later decision once
  projects have seen output.
- **Schema version stays `1`.** The key is additive and optional. Release as `1.6.0`.
- **Delivered as a stack** (proc-02 §11: dependency chain standard → scripts → docs,
  and well past the size threshold): `01-spec` (this document and the plan),
  `02-scripts` (the key, assembly, skills gate, lint loop, doctor, detection, tests),
  `03-content` (blocks, `arch-07` sections, `arch-11`, skills, the web-tells check,
  catalog, regenerated lists), `04-docs` (everything in the documentation table, the
  ADR, the changelog, the blog post). Each layer stands alone: with `02-scripts`
  merged and nothing above, a declared profile is valid, selects a block that does not
  yet exist (skipped with a warning, as a missing role block is today) and installs no
  skill.

## Errors

| Condition | User sees | Logged | Recovery |
|-----------|-----------|--------|----------|
| Unknown profile in `.standards.yml` or `--profiles` | `Unknown profile: <x> (expected one of: shared-core, ui-surface)`; setup and sync exit 2 before any write | the usage error line | fix the file; nothing was changed |
| Declared profile whose block file is absent (a stale `.standards/` pin) | `⚠️ profile block profile-<x>.md not found; skipping` and the sync continues | the warning | `make update-standards` |
| Profile skill destination exists and is `customized` or `foreign` | `kept; new version staged to .standards-pending/…` (existing behavior) | the warning | `/merge-standards` |
| Profile un-declared, installed skill `customized` | `⚠️ .claude/skills/<x>/SKILL.md is no longer managed (profile <x> not declared) — left as is` | the warning | delete by hand or re-declare |
| `web-tells` finds hits | one `WARN web-tells N hit(s): a.css:12, b.tsx:40 … (+k more); allowlist: .standards-ui-allow` | the result line in every format | add a ruled exception to the allowlist or fix the tell |
| `detect-profiles.sh` suggests a profile that is not declared | `ℹ️ INFO Profiles  shared-core looks applicable (uniffi in Cargo.toml) — declare it under profiles: to opt in` | — | opt in or ignore; INFO never fails doctor |
| `lint-checks/profiles/<x>/` missing for a declared profile | nothing; the loop skips an absent directory silently | — | none needed; `shared-core` ships no checks in v1 |

No asynchrony; no late responses to guard.

## Testing

All shell; functional tests in the style of `scripts/test-setup-safe.sh` (a temp
project per case). Coverage for shell scripts in this repo is behavioral, not
line-measured; every new branch in the list below has a test.

- **`scripts/test-profiles.sh` (new, in `make test` and CI):** inline and block list
  parsing; absent means none; unknown profile fails setup and sync with the valid list;
  one profile puts its block in every assembled agent config after the role block and
  the other profile's block nowhere; `--dry-run` announces and writes nothing; a
  missing block file warns and continues; `assemble-skills.sh --profiles` installs a
  `profiles:` skill only when declared, leaves unconditional skills alone, removes an
  `ours` copy and warns on a `customized` copy when un-declared; the index agents'
  `## Skills` section lists only declared-profile skills; `detect-profiles.sh` suggests
  each profile from a minimal fixture and nothing from an empty project; doctor's three
  outcomes.
- **`scripts/test-lint-standards.sh` (extended):** the profiles loop runs the check
  only when declared; `web-tells` WARN output well formed in text, JSON and SARIF; the
  allowlist suppresses a matching path; no hits is PASS.
- **`scripts/test-setup-safe.sh` (extended):** `--profiles` flag, written stanza,
  unknown value rejected like an unknown agent.
- **Existing gates:** `make test`, `make check-agent-configs` (regenerated lists and
  the `arch-11` catalog row), ShellCheck, markdownlint, `lint-standards.sh .`
  (dogfood; `doc-lint` validates the new ADR).
- **Manual:** none. The confidentiality rule is reviewed by reading each layer's diff
  and commit messages before `gh stack submit`; a grep for a private-term list kept
  outside the repository is the author's backstop.

## Left to the plan

- Exact wording of the two blocks, the tenets, the decision tree, the audit items and
  the two skills, within the constraints above.
- Whether `--profiles` is a flag or an environment variable on `assemble-config.sh`
  (its option parser is positional-after-flags today).
- The detection heuristics' exact file patterns.
- Test fixture layout and which existing test files absorb which cases.
- The ADR's exact title and the blog post's angle.
- Whether `scripts/lint-checks/README.md`'s enforced-vs-standards-only table gains a
  "Profiles" row or a separate section.

## Sources

- yetone, *native-feel-skill*, MIT, <https://github.com/yetone/native-feel-skill>: the
  form of the tenets file and the source lists for the `ui-surface` audit. Its
  architecture is not adopted.
- This repo: `arch-05` §2–3, `arch-07`, `proc-01` §11, `proc-02` §11, `proc-04` §7–8,
  `role-app.md`, `scripts/lib/skills.sh`.
