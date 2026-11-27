# Website Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle homepage, docs and blog in a warm dark, coder-flavoured look from the C65 family, with a C65 logo footer on every page.

**Architecture:** One token stylesheet and shared `Wordmark` and `SiteFooter` components serve both the custom homepage (`src/pages/index.astro`) and Starlight (custom CSS plus component overrides). Behaviour is pinned by `node:test` tests that read the built `dist/`.

**Tech Stack:** Astro 7, Starlight 0.43, starlight-blog, `@fontsource-variable/figtree@5.3.0`, `@fontsource-variable/jetbrains-mono@5.3.0`, `node:test`.

**Spec:** `docs/superpowers/specs/2026-11-27-website-c65-redesign-design.md`

## Global Constraints

- Tokens (dark / light): page `#1f1b19` / `#f6efe6`; panel `#2a2522` / `#fffaf3`; footer `#171412` / `#2d2926`; heading `#f6efe6` / `#2d2926`; body `#c4b5a6` / `#54483f`; accent `#e8935f` / `#8d4021`; rules `#453c36` / `#cdb9a6`. Logo ember `#dd8554`.
- JetBrains Mono for headings, navigation, labels and code; Figtree for body. No serif.
- Fonts self-hosted. CSP is not loosened: no inline event handlers, no new `'unsafe-inline'`; `inlineStylesheets: 'never'` stays.
- No blinking cursor or other looping decoration.
- Homepage is dark only. Light mode exists on docs and blog.
- WCAG AA contrast in both themes. Works at 375px with no horizontal page scroll.
- Thin rules between sections, 4–6px corners, left-aligned.
- New dependency versions at least 72 hours old.
- Do not change anything under `scripts/` at the repo root; do not commit `.superpowers/`.
- Conventional Commits. One issue, one branch, one PR.
- All commands below run from the worktree root. `npm run build` runs the content sync and the CSP step.

## Review Focus

1. Returning visitor whose stored theme is `''` (Starlight writes it for everyone who has visited): keeps Auto, is not forced to dark. Pinned in Task 3.
2. Storage blocked (private window): the theme seed script must not throw. Task 3.
3. No JavaScript or no clipboard API: no dead copy button; the command stays selectable. Task 4.
4. A source document whose first content is not a `#` heading, or has `#` lines in a code block: nothing but a leading title heading is removed. Task 1.
5. 375px width with the long install command and `.github/copilot-instructions.md`: wraps, no sideways scroll. Browser check in Task 6.

## File Structure

| File (under `website/`) | Responsibility |
|---|---|
| `scripts/strip-title.sh` (new) | Remove a leading `#` heading from a copied Markdown file |
| `src/styles/tokens.css` (new) | `--cs-*` colour and font tokens, both themes |
| `src/styles/starlight.css` (new) | Map tokens onto Starlight |
| `src/components/Wordmark.astro` (new) | `{ } coding-standards` link |
| `src/components/SiteFooter.astro` (new) | C65 logo footer |
| `src/components/starlight/{SiteTitle,Footer,ThemeProvider}.astro` (new) | Starlight overrides |
| `src/pages/index.astro` (rewrite) | Homepage |
| `tests/*.test.mjs` (new) | Assertions over sources and `dist/` |

---

### Task 1: Issue, test harness, and duplicate titles

**Files:**

- Create: `website/scripts/strip-title.sh`, `website/tests/titles.test.mjs`, `website/tests/helpers.mjs`
- Modify: `website/scripts/sync-content.sh`, `website/src/content/docs/why.md`, `website/package.json`, `Makefile`, `.github/workflows/ci.yml` (`build-website` job)

**Interfaces:**

- Produces: `helpers.mjs` exports `page(route: string): string` (HTML of `dist/<route>/index.html`, `''` = homepage), `allPages(): {file: string, html: string}[]`, `textOf(html: string): string` (tags stripped, entities decoded, whitespace collapsed). `npm test` runs `node --test tests/*.test.mjs`. `make test-website` builds then tests.

- [ ] **Step 1:** Open the GitHub issue with `gh issue create` (title "Redesign the website in the C65 family"; body links the spec). Use its number in commits and the PR.
- [ ] **Step 2: Write the failing tests** in `titles.test.mjs`:

```js
test('no page repeats its title as a second h1', () => {
  for (const { file, html } of allPages()) {
    const h1s = [...html.matchAll(/<h1\b[^>]*>([\s\S]*?)<\/h1>/g)].map((m) => textOf(m[1]));
    assert.equal(new Set(h1s).size, h1s.length, `${file}: ${h1s.join(' | ')}`);
  }
});

test('strip-title removes only a leading heading', () => {
  // run `bash scripts/strip-title.sh <tmpfile>` on each input and compare the file
  const cases = [
    ['---\ntitle: "A"\n---\n\n# A\n\nbody\n', '---\ntitle: "A"\n---\n\n\nbody\n'],
    ['---\ntitle: "A"\n---\n\nintro\n\n# Later\n', null], // unchanged
    ['---\ntitle: "A"\n---\n\n```bash\n# comment\n```\n', null],
    ['---\ntitle: "A"\n---\n\n## Sub\n', null],
  ];
});

test('why page states 14 languages', () => {
  assert.match(textOf(page('why')), /14 languages/);
});
```

- [ ] **Step 3:** Add the `test` script and `make test-website` (`cd website && npm run build && npm test`, listed in `.PHONY` and `help`; not part of `make test`). Run `cd website && npm ci && npm run build && npm test`. Expected: the three tests FAIL.
- [ ] **Step 4:** Implement `strip-title.sh <file>` (portable awk, macOS and Linux): after the closing frontmatter `---`, if the first non-blank line starts with `#`, delete that line. Call it from `sync-content.sh` on every copied `.md` file, after all copies. Sources are never modified.
- [ ] **Step 5:** In `why.md` delete the `# Why Coding Standards?` line and change `13 languages` to `14 languages`.
- [ ] **Step 6:** Add a `Test website` step (`cd website && npm test`, same `if:` as the build step) after `Build website` in `ci.yml`.
- [ ] **Step 7:** Run `make test-website && make test-scripts`. Expected: PASS.
- [ ] **Step 8: Commit** `fix(website): stop docs pages repeating their title`.

### Task 2: Tokens, fonts, and the docs/blog theme

**Files:**

- Create: `website/src/styles/tokens.css`, `website/src/styles/starlight.css`, `website/tests/theme.test.mjs`
- Modify: `website/astro.config.mjs` (`customCss`), `website/package.json`, `website/package-lock.json`

**Interfaces:**

- Produces: custom properties `--cs-bg`, `--cs-panel`, `--cs-footer`, `--cs-heading`, `--cs-text`, `--cs-accent`, `--cs-rule`, `--cs-footer-text` (`#d9cbbd`), `--cs-ember` (`#dd8554`), `--cs-mono` (`'JetBrains Mono Variable', ui-monospace, monospace`), `--cs-sans` (`'Figtree Variable', system-ui, sans-serif`). Dark values on `:root`, light on `:root[data-theme='light']`.

- [ ] **Step 1: Write the failing tests.** Parse the two blocks of `tokens.css` and assert:

```js
// every value in the Global Constraints table, per theme
// contrast(--cs-text, --cs-bg) >= 4.5, also on --cs-panel; same for --cs-heading and --cs-accent
// contrast(--cs-footer-text, --cs-footer) >= 4.5
// every dist CSS/HTML: no 'fonts.googleapis.com' or 'fonts.gstatic.com'
// dist contains at least one .woff2 file for each of figtree and jetbrains-mono
```

- [ ] **Step 2:** Run `make test-website`. Expected: FAIL, `tokens.css` missing.
- [ ] **Step 3:** `cd website && npm install --save-exact @fontsource-variable/figtree@5.3.0 @fontsource-variable/jetbrains-mono@5.3.0`.
- [ ] **Step 4:** Write `tokens.css`. If a pair fails contrast, adjust that token and record the change in the spec's table.
- [ ] **Step 5:** Write `starlight.css` and set `customCss` to the two font packages, `tokens.css`, `starlight.css`. Map `--sl-color-{bg,bg-nav,bg-sidebar,text,text-accent,white,black,gray-1…7,accent-low,accent,accent-high,hairline,hairline-light,hairline-shade}`, `--sl-font`, `--sl-font-mono` for both themes (note Starlight's `white`/`black` invert in light). Headings, header, sidebar group labels use `--cs-mono`; 4–6px corners.
- [ ] **Step 6:** Run `make test-website`. Expected: PASS.
- [ ] **Step 7: Commit** `feat(website): theme docs and blog in warm dark`.

### Task 3: Wordmark, footer, and dark by default

**Files:**

- Create: `website/src/components/Wordmark.astro`, `website/src/components/SiteFooter.astro`, `website/src/components/starlight/{SiteTitle,Footer,ThemeProvider}.astro`, `website/tests/chrome.test.mjs`
- Modify: `website/astro.config.mjs` (`components`)

**Interfaces:**

- Consumes: `--cs-*` tokens.
- Produces: `<Wordmark />` and `<SiteFooter />`, no props, styled only with tokens. `SiteFooter` root is `<footer class="site-footer">`.

- [ ] **Step 1: Write the failing tests.**

```js
// for every dist page except the homepage (Task 4 adds it):
//   exactly one .site-footer; it contains a[href="https://www.c65llc.com/"] with an
//   <svg role="img" aria-label="C65">, the text "a C65 project", "C65 LLC", and links to
//   /getting-started/quick-start/, /blog/, /rss.xml, https://github.com/c65llc/coding-standards
// a docs page with neighbours still contains Starlight's pagination links (rel="next" or rel="prev")
// 404.html has the footer
// seed script, extracted from a built docs page and run with node:vm against a fake localStorage:
//   getItem -> null   => setItem('starlight-theme','dark') called
//   getItem -> ''     => setItem not called
//   getItem -> 'light'=> setItem not called
//   getItem throws    => does not throw
// the seed script appears in <head> before Starlight's theme script
```

- [ ] **Step 2:** Run `make test-website`. Expected: FAIL.
- [ ] **Step 3:** Write `SiteFooter.astro`. SVG: `viewBox="89.8 156 280.4 148.4"`, 76×40, "C" fill `#f6efe6`, "65" fill `var(--cs-ember)`. Path data, verbatim:

```text
C:  M216 156H164A74.2 74.2 0 0 0 164 304.4H192.5A64.4 64.4 0 0 1 172 278.8H164A48.6 48.6 0 0 1 164 181.6H199.5Z
65: M231.6 157.2H262.5L208.5 238.3A25.8 25.8 0 1 0 233 226.9L247.7 203.7A51.6 51.6 0 1 1 187.2 224ZM278.4 158.4H369.2V183.7H261.2ZM283.2 215.3A51.5 51.5 0 1 1 283.2 289.5A64.8 64.8 0 0 0 293.9 266A28.4 28.4 0 1 0 293.9 239A64.8 64.8 0 0 0 283.2 215.3Z
```

- [ ] **Step 4:** Write `Wordmark.astro` (`{ }` in accent, `coding-standards`, links to `/`).
- [ ] **Step 5:** Write the overrides. `Footer.astro` renders Starlight's default `Footer`, then `<SiteFooter />`; on docs pages it is a panel within the content column (the fixed sidebar rules out full bleed). `ThemeProvider.astro` renders an `is:inline` script that sets `starlight-theme` to `dark` only when `getItem` returns `null`, inside `try`, followed by the default `ThemeProvider`. `SiteTitle.astro` renders `<Wordmark />`. Do not override `ThemeSelect` or `MarkdownContent`; starlight-blog owns them.
- [ ] **Step 6:** Run `make test-website`. Expected: PASS, including the CSP step in the build.
- [ ] **Step 7: Commit** `feat(website): add C65 footer and wordmark, default to dark`.

### Task 4: Homepage

**Files:**

- Rewrite: `website/src/pages/index.astro` (split into `src/components/home/*.astro` if it passes ~300 lines)
- Create: `website/tests/home.test.mjs`

**Interfaces:**

- Consumes: `tokens.css`, the two font packages, `<Wordmark />`, `<SiteFooter />`.

- [ ] **Step 1: Write the failing tests** over `page('')`:

```js
// h1 text === 'Write the rule once.'  and <html> has data-theme="dark"
// hero lead: 'One set of coding standards, compiled into the file each AI agent already reads.'
// install command appears twice: curl -fsSL https://raw.githubusercontent.com/c65llc/coding-standards/main/install.sh | bash
// source panel: contains the three lines of standards/shared/blocks/architecture-core.md starting at
//   'Validate inputs at boundaries.' (read the file in the test), with their real line numbers
// all six: CLAUDE.md, AGENTS.md, .cursorrules, .github/copilot-instructions.md,
//   .gemini/GEMINI.md, .aider-instructions.md
// section#why: h2 'Why coding standards?'; 3 lines starting '-' and 3 starting '+' in the text;
//   labels '// sync', '// architecture', '// setup', '// updates'; a[href="/why/"];
//   'Customized agent configs are never overwritten'
// languages: Python, Java, Kotlin, Swift, Dart, TypeScript, JavaScript, Rust, Zig, Ruby,
//   Ruby on Rails, Go, Elixir, C++
// #usage: five hrefs sostalog.com, dopotasks.com, pigeonpile.com/apps/wiki, sprigedit.com,
//   awayteamapp.com; links to www.c65llc.com and pigeonpile.com
// exactly one .site-footer
// every copy <button> has the hidden attribute in the built HTML
// no 'The Problem', no 'six leading'
// meta og:title, og:description, og:image, rel=sitemap and rel=alternate rss still present
```

Also remove the homepage exclusion from the footer test in `chrome.test.mjs`.

- [ ] **Step 2:** Run `make test-website`. Expected: FAIL.
- [ ] **Step 3:** Build the sections in the spec's order (header, hero, source/output, why, how it works, languages, built with it, closing call, footer), following the approved mockup in `.superpowers/brainstorm/*/content/why-section-v3.html` (skin `c2`) if present.
  - Import the rule file with `?raw` and compute line numbers; throw at build if the first line is not found.
  - Diff panel copy: `- Each tool configured separately, and the configs contradict each other` / `- Standards live in a wiki page nobody reads, and drift` / `- Code review spent on style instead of logic bugs` / `+ One source of truth, compiled for every agent` / `+ The same architecture and naming in every repository` / `+ Review time goes to what the code does`. Lead: `Every agent has its own habits. Without shared rules your codebase becomes a patchwork that is harder to review and maintain.`
  - Four points: Multi-agent sync "No more conflicting styles across tools." / Clean architecture "The same principles across 14 languages." / One command "Rules land where each agent expects them." / Stays current "Git hooks re-sync. Customized agent configs are never overwritten."
  - How it works: the current three `steps`, with Aider added to step 2's list.
  - Usage entries and sentence: carry over unchanged, with the "keep in step with README" comment.
  - Page title and meta description stay; the description gains no new claims.
  - Copy button: rendered `hidden`; a bundled `<script>` unhides it only when `navigator.clipboard` exists; label `copy`, then `copied`, or `select and copy` on rejection; `aria-live="polite"`.
- [ ] **Step 4:** Run `make test-website`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(website): redesign the homepage`.

### Task 5: Favicon and social image

**Files:**

- Modify: `website/public/favicon.svg`, `website/public/og-image.png`
- Create: `website/scripts/og-image.html` (source the PNG is captured from), `website/tests/assets.test.mjs`

- [ ] **Step 1: Write the failing tests:** `favicon.svg` contains `#e8935f` and `#1f1b19` and not `#1a1a2e`; `og-image.png` IHDR is 1200×630.
- [ ] **Step 2:** Run `make test-website`. Expected: favicon test FAILS.
- [ ] **Step 3:** Redraw the favicon: `{ }` in `#e8935f` on a `#1f1b19` rounded square.
- [ ] **Step 4:** Write `og-image.html` (wordmark, "Write the rule once.", the one-line lead, C65 logo; local fonts from `node_modules`) and capture it at 1200×630 with headless Chrome or Playwright. Open the PNG and check the fonts rendered.
- [ ] **Step 5:** Run `make test-website`. Expected: PASS.
- [ ] **Step 6: Commit** `feat(website): refresh favicon and social image`.

### Task 6: Verify and open the PR

- [ ] **Step 1:** Run `make test-website test-website-csp test-scripts lint-standards` and `shellcheck -x --severity=warning website/scripts/*.sh`. Expected: all pass; report any not run.
- [ ] **Step 2:** Serve `website/dist` with a throwaway server that applies the `/*` headers from `dist/_headers` (kept in the scratchpad; `astro preview` does not send them). Follow `docs/deploy.md` "Verifying a CSP change" items 1–5.
- [ ] **Step 3:** Screenshot homepage, a standards page with code blocks, a blog post, the blog list and 404 at desktop and 375px; docs and blog also in light. At 375px assert `document.documentElement.scrollWidth <= 375` on each. Fix what fails, with a test where one can pin it.
- [ ] **Step 4:** Check keyboard focus is visible on header links, copy buttons and footer links in both themes.
- [ ] **Step 5:** Commit any remaining fixes, push, and open the PR (Conventional Commits title, `Closes #<issue>`, proc-05 evidence table with tested SHA). Note in the PR: `index.mdx` is unreachable and untouched; returning visitors keep Auto; the Cloudflare preview CSP check is still owed until done there.
