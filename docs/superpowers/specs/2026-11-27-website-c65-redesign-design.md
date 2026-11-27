# Website Redesign: Warm Dark, in the C65 Family — Design Spec

- **Status:** Agreed
- **Date:** 2026-11-27
- **Scope:** `website/` (homepage, docs, blog)

## Purpose

The marketing site should be visibly part of the same family as
<https://www.c65llc.com/> while still reading as a tool for programmers. Strict
adherence to C65 branding is not required. A C65 logo in the footer is required.

Today the homepage is a near-black, purple-accented page of boxed cards, and the
docs and blog are the stock Starlight theme. Neither relates to C65.

## Goals

- One look across homepage, docs and blog: warm dark, C65 colours, coder cues.
- The C65 logo in the footer of every page.
- A homepage that shows what the product does: a rule, and the files it lands in.
- Correct facts on the homepage.

## Non-goals

- Replacing Starlight, or changing docs/blog structure, search or navigation.
- Rewriting docs or blog content (old posts keep their original claims).
- Changing c65llc.com.

## Anti-goals

- A page that looks like a copy of c65llc.com.
- A generic dark developer site that has lost the warm browns.
- A blinking cursor, or other looping decoration.
- Loosening the Content-Security-Policy.

## Approaches

1. **Shared theme (chosen).** One token stylesheet and one footer component used
   by a custom homepage and by Starlight. The homepage can match the mockup
   closely. Cost: the header exists twice (homepage, and restyled Starlight).
2. **Homepage as a Starlight page.** One header, search and footer. Cost: the
   layout has to work around Starlight's page styles and is more likely to break
   on upgrades.
3. **Custom pages instead of Starlight (rejected).** Loses search and sidebar for
   a visual gain.

## Look

Chosen from mockups: layout "C, show the work" with the "C2, warm dark" skin,
without the blinking cursor.

| Token | Dark | Light (docs/blog only) |
|---|---|---|
| Page background | `#1f1b19` | `#f6efe6` |
| Panel | `#2a2522` | `#fffaf3` |
| Footer | `#171412` | `#2d2926` |
| Heading text | `#f6efe6` | `#2d2926` |
| Body text | `#c4b5a6` | `#54483f` |
| Accent | `#e8935f` | `#8d4021` |
| Rules | `#453c36` | `#cdb9a6` |

- **Type:** JetBrains Mono for headings, navigation, labels and code; Figtree for
  body text. No serif.
- **Coder cues:** `{ } coding-standards` wordmark, `$` prompt on the install
  command, window-style panels with file names, line numbers, a file tree,
  `// label` tags.
- Thin rules between sections, 4–6px corners, left-aligned.
- Text must meet WCAG AA contrast in both themes; adjust a token if it does not.
- Layout works at 375px wide with no horizontal page scroll.

## Homepage

In order:

1. **Header:** wordmark; docs, blog, usage, github, RSS.
2. **Hero:** "Write the rule once." / "One set of coding standards, compiled into
   the file each AI agent already reads." / install command with a copy button.
3. **Source and output:** two panels. Left: a few lines of a rule that really is
   copied into generated configs, from
   `standards/shared/blocks/architecture-core.md` (the error-handling lines).
   Right: the file tree of agent files.
4. **Why coding standards?** (`#why`):
   - one lead sentence on the problem (agents have their own habits);
   - a diff panel, three `-` lines (separately configured, contradicting tools;
     a wiki page nobody reads, drifting; review spent on style) and three `+`
     lines (one source of truth; same architecture and naming everywhere;
     review time on what the code does). The `-`/`+` marks carry the meaning,
     not colour alone;
   - four points: `// sync` multi-agent sync; `// architecture` clean
     architecture across 14 languages; `// setup` one command; `// updates` a
     post-merge hook flags updates (it does not sync by itself), and customized
     agent configs are never overwritten.
     *(Author's call: sync does overwrite some other files, such as language
     tool configs and `.gemini/settings.json`, so the claim is limited to agent
     configs. Changing sync is out of scope.)*
   - a link to `/why/`.
5. **How it works:** the three existing steps (install, sync, consistent code),
   as ruled rows.
6. **Languages:** all 14 (Python, Java, Kotlin, Swift, Dart, TypeScript,
   JavaScript, Rust, Zig, Ruby, Ruby on Rails, Go, Elixir, C++).
7. **Built with it:** the five apps now listed, as ruled rows, keeping the
   `#usage` anchor and the C65 and Pigeonpile sentence.
8. **Closing call:** install command and a link to the docs.
9. **Footer.**

The agent tree lists six agents: `CLAUDE.md` (Claude Code), `AGENTS.md` (Codex),
`.cursorrules` (Cursor), `.github/copilot-instructions.md` (Copilot),
`.gemini/GEMINI.md` (Gemini CLI), `.aider-instructions.md` (Aider).

The separate "Problem / Solution" boxes and icon feature cards are replaced by
item 4.

## Footer

One component, used on every page including 404:

- C65 logo, two-tone as on c65llc.com (cream "C", ember `#dd8554` "65"), inline
  SVG, linking to <https://www.c65llc.com/>, with an accessible name.
- "a C65 project", links to docs, blog, GitHub, RSS and c65llc.com, and
  "© <year> C65 LLC".
- The footer is dark in both themes.

The logo path data is taken from the footer of c65llc.com.

On docs pages the footer must not replace Starlight's previous/next links,
edit link or last-updated line.

## Docs and blog

- Same tokens and fonts, applied through Starlight's custom CSS properties and,
  where needed, component overrides.
- Warm dark when the visitor has made no choice, including on a light-mode
  system. Starlight's theme selector keeps working, and an explicit Light or
  Auto choice is respected.
- **Duplicate titles:** `website/scripts/sync-content.sh` keeps each source
  file's `# Heading` while Starlight also renders the frontmatter title. The sync
  step drops that first heading from the copied files only; sources are
  untouched. `why.md` is written directly in the site, so remove its repeated
  `# Why Coding Standards?` line there, and correct its language count from 13 to
  14.
- `src/content/docs/index.mdx` shares the `/` route with the custom homepage and
  is not served. Leave it alone and say so in the PR. *(Author's call.)*

The homepage is dark only.

## Assets

- `public/favicon.svg`: `{ }` in ember on warm charcoal.
- `public/og-image.png`: 1200×630, redrawn in the new look.

## Constraints

- Fonts are self-hosted (for example `@fontsource-variable/*` packages); the CSP
  is `font-src 'self'`. New dependencies follow the repo's dependency age gate.
- No inline event handlers and no new `'unsafe-inline'`:
  `scripts/csp-postbuild.mjs` fails the build otherwise.
- CSS ships as files (`inlineStylesheets: 'never'`).
- The site stays static; the copy button is the only new script and the page is
  fully usable without it.

## Verification

- `cd website && npm ci && npm run build` passes, including the CSP step.
- Screenshots of homepage, a docs page, a blog post and 404 at desktop and 375px,
  in dark and (docs/blog) light.
- No CSP violations in the browser console on a preview of the built site;
  `docs/deploy.md` asks for a Cloudflare Pages preview check on CSP-affecting
  changes.
- Search still works on the built site.

## Delivery

One GitHub issue, one branch, one PR, Conventional Commits. The mockup directory
`.superpowers/` is not committed.

## Left to the builder

File and component names, spacing and type scale, breakpoints, how the Starlight
overrides are done, and how the social image is produced.
