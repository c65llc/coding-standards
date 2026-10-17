# Document Templates

Copy-and-fill templates for the documents that
[proc-01_documentation_standards.md](../../standards/process/proc-01_documentation_standards.md)
asks for. They mirror the shapes consumer projects converged on in practice
(see issue #196), so a reader moving between projects sees the same sections
in the same order.

| Template | Copy to | When | Lifecycle |
|----------|---------|------|-----------|
| [`adr.md`](adr.md) | `docs/adr/NNNN-[title].md` | A decision changes structure, dependencies or a significant technical choice | Live until Superseded; never deleted |
| [`spec.md`](spec.md) | `docs/specs/YYYY-MM-DD-[topic]-design.md` | Before planning any non-trivial feature | Live while Draft/Agreed; historical once Implemented |
| [`plan.md`](plan.md) | `docs/plans/YYYY-MM-DD-[topic]-plan.md` | After the spec is agreed, before the first commit | Historical: tick boxes, never rewrite |
| [`design-pass.md`](design-pass.md) | `docs/design/YYYY-MM-DD-[surface].md` | Before writing UI code for a new or reshaped surface | Live until Built; then historical |
| [`verification.md`](verification.md) | `docs/[feature]-verification.md` | With the PR that ships the feature | Historical: a point-in-time record |

Projects that use the `superpowers` workflow keep specs under
`docs/superpowers/specs/` and plans under `docs/superpowers/plans/`; the
template content is identical.

## Conventions shared by every template

- **Bullet metadata at the top** (`- **Status:**`, `- **Date:**`,
  `- **Related:**`) so `lint-standards` and humans can find the fields without
  parsing headings. ADRs additionally carry `Supersedes` / `Extends`.
- **Placeholders are square brackets** — `[like this]`, `[topic]`, `[N]` — and
  must not survive into a committed document. A quick check that covers both
  the capitalised prompts and the lowercase slot names, while skipping
  `[text](link)`, `[label]: url` and ticked `[x]` checkboxes:

  ```bash
  grep -nE '\[[A-Za-z][^]]*\]($|[^(:])' docs/your-file.md | grep -v '\- \[x\]'
  ```

- **No "Alternatives considered" section by default.** State the rejected
  option inline in the Decision when it matters.
- **Every doc appears in the docs index** with a `live` or `historical`
  status (proc-01 §9).
- The `doc-lint` check in `scripts/lint-checks/common/` verifies ADR required
  fields and that relative links resolve. Run it before opening the PR:
  `./.standards/scripts/lint-standards.sh .` in a project that installed the
  standards (`install.sh` adds only the `sync-standards` and `diff-standards`
  Make targets), or `make lint-standards` inside the standards repo itself.
