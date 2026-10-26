---
title: "Profiles: Opt In to Standards by Product Shape"
date: 2026-10-22
authors:
  - name: C65 LLC
---

Some standards do not follow from the language you write in or the role your
project plays. They follow from the *shape* of the product: one logic core
under three native shells, or a web app that has to pass for a native one. Until
now `.standards.yml` had no way to say that, so those standards either reached
every project as noise or reached nobody.

Release 1.6.0 adds **profiles**: a third selector axis, opt-in, with two
profiles to start.

## What a profile is

A profile is one line in `.standards.yml`:

```yaml
profiles:
  - shared-core
  - ui-surface
```

On the next `make sync-standards`, a block
lands in every assembled agent config under a `## Profiles` heading, after the
role block. The profile's skill is installed for the agents that read skill
files (Claude Code, Cursor, Copilot) and indexed for the ones that read a single
config (Codex, Gemini, Aider). The profile's lint checks become eligible for
`make lint-standards` or CI, scoped like a language check; sync does not run them.

A project that declares nothing is byte-for-byte unchanged. That is the
property we cared most about: an optional standard that leaks into projects
that did not ask for it is not optional.

## shared-core

For products built as one logic core, in Rust or compiled to WASM and FFI,
under thin native shells. The existing `arch-07` standard already said what to
do; it now also says *why*, as ten numbered tenets an agent or a reviewer can
cite by short name (`T3 — inject ambient inputs`, `T10 — name what you give
up`). It gains a platform-shape decision tree that is allowed to answer "not
this shape" — a tab web app or a single-platform native app is often correct,
and saying so is the useful outcome — and a native-shell ship audit to walk on
the running app before calling a shell done.

The `shared-core` skill routes an agent to the right section, makes it run the
decision tree before recommending a shape, and makes it name what each
recommendation costs.

## ui-surface

For any project that ships a UI people use on a desktop or mobile platform,
including a web app installed as a PWA. The new `arch-11` standard starts from
one rule: the platform owns the window, selection, spelling, the context menu,
scrolling, focus order and the accessibility tree, and the design system owns
what is inside the frame. It carries ownership tables for three surface classes
(browser tab, installed PWA, native shell) and a 67-item audit, each item tagged
by the surfaces it applies to: no pointer cursor on rows, no selectable chrome
text, no smooth-scroll polyfills, no route fades, platform dialogs rather than
DOM overlays, loading that shows nothing under 200 ms.

The standard also says when *not* to follow the audit. A product accumulates
decisions that are better than generic — where its save state lives, which
surface adopts a skeleton and why — and where a project keeps those as a
rulings ledger and platform primers, the ruling wins and the change cites it.

`ui-surface` ships one lint check, `web-tells`, which reports `cursor:
pointer`, smooth-scroll overrides and selectable chrome in stylesheets and
scripts. It only warns, and a deliberate exception goes in a committed
`.standards-ui-allow`, one glob per line, so the decision is written down
where review can see it instead of the check being switched off.

## Skills that know their profile

The agent-neutral skills under `standards/skills/` gained a `profiles:`
frontmatter key. A skill that carries it installs only when that profile is
declared, and un-declaring the profile removes the installed copy when it is
still the file the standards wrote. An edited copy is kept and reported as no
longer managed, so a project that built on a skill never loses the work.

## Suggest, never enable

`make doctor` prints an INFO line when `scripts/detect-profiles.sh` thinks a
profile applies — a `uniffi` dependency in `Cargo.toml`, a web app manifest,
`role: app` — fails on an unknown profile name, and warns when a declared
profile's skill is not installed. The setup wizard asks the same question. None
of them writes the line for you. The only thing that enables a profile is the
committed `.standards.yml`, which is what makes a profile reviewable.

## Getting it

```bash
make update-standards      # pull 1.6.0
# add profiles: to .standards.yml
make sync-standards
make doctor
```

The schema reference documents the key, the customization guide covers adding
and removing a profile, and the lint-checks README lists `web-tells` beside the
language checks.
