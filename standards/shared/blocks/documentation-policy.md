# Documentation Policy

Document all public APIs with language-standard formats (JSDoc, docstrings, rustdoc, JavaDoc, YARD). Include parameters, return values, errors, and examples.
Comments explain "why", never "what". Self-documenting code preferred.
Every package and app must have a README: purpose, installation, usage, configuration, development.
Create an ADR in `docs/adr/` for decisions affecting structure, dependencies, or significant technical choices.
Maintain `CHANGELOG.md` (Keep a Changelog format). Update for every user-facing change in a PR.
Track all work as GitHub Issues. Every `TODO`/`FIXME` must reference an issue: `# TODO(#42): description`.
