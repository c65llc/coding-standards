# ADR 0002: Add profiles as a third selector axis in .standards.yml

- **Status:** Accepted
- **Date:** 2026-10-22
- **Related:** #227, `docs/superpowers/specs/2026-10-17-standards-profiles-design.md`
- **Supersedes:** —
- **Extends:** ADR 0001 (the unified standards repository and its agent-config assembly)

## Context

`.standards.yml` selected assembled content along two axes: `languages` (one
block per language) and `role` (one block for `service`, `library`, `app` or
`data-pipeline`). Everything else in the standards tree was either injected
into every project or never injected at all.

Two bodies of knowledge fell through that gap. `arch-07` (cross-platform
shared-core) applies to one product shape and reached no agent config because
nothing could say "this project has that shape." Platform-feel conventions —
the details that make a UI read as an app rather than a web page in a frame —
had no standard at all. Both are opt-in by nature: a web service wants neither,
a single-platform web app wants only the second, a multi-platform suite wants
both. Injecting either everywhere would be noise for most projects; leaving
them out keeps repeating the same mistakes in the projects that need them.

Three shapes were considered for the selector:

- a new value of `architecture` (`clean` | `none` | `shared-core`), rejected
  because `architecture` is an enforcement level and a project can be `clean`
  with or without a shared core;
- a `skills:` list naming individual skills to install, rejected because it
  conflates the skill with the standard it serves and leaves the block and the
  lint checks with no selector;
- a `profiles:` list, where each value names a block, a standard, a skill and a
  lint-check directory together.

## Decision

We add an optional `profiles` list to `.standards.yml` as a third selector axis
beside `languages` and `role`, with a fixed, documented set of values
(`shared-core`, `ui-surface`) maintained in this repository rather than a
plugin mechanism. A declared profile injects `profile-<name>.md` under one
`## Profiles` heading after the role block, installs the skill whose frontmatter
carries `profiles: <name>`, and enables `lint-checks/profiles/<name>/`.

Nothing enables a profile but the committed `.standards.yml`: `doctor` and
`detect-profiles.sh` only suggest. An unknown name is a usage error before any
write. Un-declaring a profile removes its installed skill only when the file is
still the one the standards wrote; an edited copy is kept and reported.

We render all profile blocks under one `## Profiles` heading with a sub-heading
per profile rather than one `##` per profile, so the `merge-standards` heading
list grows by one entry rather than one per future profile. Profile lint checks
are WARN-level in this release; promotion to FAIL is a later decision once
projects have seen the output. The schema version stays `1` because the key is
additive and optional.

## Consequences

Easier: a project opts in to a product-shape standard with one line, and the
block and skill arrive on the next sync, and the checks run on the next
`make lint-standards` or CI invocation. A project
that declares nothing is byte-for-byte unaffected, which keeps this release a
minor version.

Harder: adding a profile is a pull request to this repository (block, standard,
skill, optional checks, tests, documentation), not a drop-in file. That is
deliberate: a profile is a standard, and standards are reviewed here.

Accepted risks: `detect-profiles.sh` heuristics may suggest a profile that does
not fit; the cost is one INFO line, never a change to the project. The
`web-tells` check reports deliberate idioms until the project records them in
`.standards-ui-allow`; the cost is a WARN, never a blocked merge.

Follow-ups: promote `web-tells` to FAIL or keep it WARN after real projects have
run it; decide whether `shared-core` ships a check of its own (a conformance
vector directory present, for instance).
