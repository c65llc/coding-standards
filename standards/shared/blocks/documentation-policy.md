Document all public APIs with language-standard formats (JSDoc, docstrings, rustdoc, JavaDoc, YARD). Include parameters, return values, errors, and examples.
Comments explain "why", never "what". Self-documenting code preferred.
Every package and app must have a README: purpose, installation, usage, configuration, development.
Create an ADR in `docs/adr/` for decisions affecting structure, dependencies, or significant technical choices.
Maintain `CHANGELOG.md` (Keep a Changelog format); update it for every user-facing change in a PR — UNLESS the project uses release automation (semantic-release, release-please, Changesets). With automation, release notes are generated from Conventional Commits: do NOT hand-edit a shared `[Unreleased]` block per PR (it causes merge conflicts under parallel work); rely on generated notes or per-PR changeset fragments.
Track all work as GitHub Issues. Every `TODO`/`FIXME` must reference an issue: `# TODO(#42): description`.
