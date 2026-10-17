# Deployment — Cloudflare Pages (Git integration)

The documentation site (`website/`, Astro + Starlight, a fully static build) is
hosted on **Cloudflare Pages**, connected to this repository through Cloudflare's
**GitHub integration**. Cloudflare runs the build and deploy itself — there are
**no API tokens or secrets stored in GitHub**. This file is a maintainer runbook;
it is not published to the site.

## How publishing works

Cloudflare Pages' **production branch is `live`** (not `main`). Cloudflare builds
and deploys whenever `live` changes.

`main` is never the production branch, so routine docs/standards merges don't
republish the site. The only thing that moves `live` is
[`.github/workflows/publish.yml`](../.github/workflows/publish.yml), which
fast-forwards `live` to the published commit — and it runs **only** on:

- a **GitHub Release being published** (`release: [published]`) — i.e. when we cut a release;
- a **blog post added/edited** on `main` (`push` to `website/src/content/docs/blog/**`); or
- a **manual run** (`workflow_dispatch`).

The workflow uses the built-in `GITHUB_TOKEN` (`contents: write`) to push `live`
— no Cloudflare credentials are involved.

```text
release published ─┐
blog post on main ─┼─▶ publish.yml ──(git push)──▶ live branch ──▶ Cloudflare Pages builds + deploys
manual dispatch  ──┘
```

## One-time setup (Cloudflare dashboard — no GitHub secrets)

1. **Connect the repo.** Cloudflare dashboard → Workers & Pages → Create →
   Pages → **Connect to Git** → authorize the Cloudflare GitHub app on
   `c65llc/coding-standards`.
2. **Build settings:**
   - **Production branch:** `live`
   - **Root directory:** `website`
   - **Build command:** `npm run build`
   - **Build output directory:** `dist`
   - Cloudflare installs deps from the committed `website/package-lock.json`.
3. **Disable preview deployments** (optional) so only `live` publishes — or leave
   them on for PR previews; they don't touch production.
4. **Custom domain:** in the Pages project → Custom domains → add
   `coding-standards.c65llc.com`. Because DNS is already on Cloudflare this is one
   click; Cloudflare issues and renews the TLS certificate automatically (no more
   HTTP 526), and the proxy stays on.
5. **Seed `live`:** run the `Publish site` workflow once (Actions → Publish site →
   Run workflow) to create/advance `live`, or `git push origin main:live` locally.

## Content-Security-Policy

Response headers live in `website/public/_headers` (Cloudflare Pages
`_headers` format). The CSP there is **hash-based** — `script-src` and
`style-src` carry no `'unsafe-inline'` — and it is finished at build time:

- `npm run build` runs `scripts/csp-postbuild.mjs` after `astro build`
  (`postbuild` hook). It hashes every executable inline `<script>` and inline
  `<style>` in `dist/**/*.html` and substitutes the `__CSP_SCRIPT_HASHES__` /
  `__CSP_STYLE_HASHES__` placeholders on the `Content-Security-Policy:` line of
  `dist/_headers`. Starlight ships ~9 inline scripts (theme provider, sidebar
  state, search shortcut); `build.inlineStylesheets: 'never'` in
  `astro.config.mjs` keeps inline `<style>` at zero.
- `'wasm-unsafe-eval'` in `script-src` is required by Pagefind (Starlight
  search), which compiles a WebAssembly module. It does not allow `eval()`.
- The step **fails the build** (and therefore the `Build Website` CI job) if an
  inline event handler appears, if the placeholders are missing, or if the
  rendered header exceeds Cloudflare's 2,000-character limit per `_headers`
  line — so a Starlight/Expressive Code upgrade that introduces new inline
  content is caught before it deploys.
- Functional tests: `make test-website-csp`
  (`website/scripts/test-csp-postbuild.sh`, part of `make test` and the
  `Test Scripts` CI job).

### Residual: inline `style` attributes

Expressive Code colours every syntax token with an inline attribute
(`style="--0:#…;--1:#…"`) and Starlight uses `style="--depth: N"` /
`--sl-icon-size`. Roughly 55 distinct values exist site-wide; their hashes
(~53 chars each) do not fit in Cloudflare's 2,000-character header line, so the
**header** keeps `style-src-attr 'unsafe-inline'`. To close that gap the
post-build step injects, at the top of every page's `<head>`,
`<meta http-equiv="Content-Security-Policy" content="style-src-attr 'unsafe-hashes' <hashes of that page's style attributes>">`
(or `'none'` for pages without any). Browsers enforce every delivered policy
and allow only what *all* of them allow, so the effective `style-src-attr`
is the exact set of attribute values present on the page — no `'unsafe-inline'`
remains in the effective policy on browsers that implement `style-src-attr`
(Chrome 75+, Firefox 108+, Safari 15.4+). Older browsers ignore
`style-src-attr`, fall back to `style-src 'self'` and lose only the inline
token colours / sidebar indentation; scripts are unaffected.

A nonce-based policy is not an option for a static site (nonces must be unique
per response), and Astro's `security.csp` was evaluated but not adopted: on
Starlight 0.42 its generated `<meta>` omits Starlight's `is:inline` scripts
(the theme toggle would be blocked), it cannot carry `frame-ancestors`, and it
does not cover `style` attributes.

### Verifying a CSP change

CSP breakage is invisible in CI (the build succeeds; the browser blocks things
at runtime), so every change to `_headers`, `csp-postbuild.mjs`, or a
Starlight / Expressive Code upgrade must be checked **against a Cloudflare
Pages preview deployment** (open the PR's preview URL from the Cloudflare
dashboard, or push the branch to a preview branch):

1. Open the preview URL with DevTools → Console. Load the home page, a
   standard page with code blocks (for example
   `/standards/languages/lang-01_python_standards/`), a blog post, and a 404.
   There must be **no** `Refused to execute inline script` /
   `Refused to apply inline style` messages.
2. **Theme toggle:** switch Dark → Light → Auto in the header. The page colours
   must change immediately and persist across a reload.
3. **Code blocks:** tokens must be coloured (not all one colour), and the copy
   button must work. Changing theme must recolour the tokens.
4. **Search:** press `/` or click Search, type a term, confirm results appear
   (this exercises `'wasm-unsafe-eval'` for Pagefind). No Console errors.
5. **Sidebar:** nested groups are indented and collapse/expand; the current
   page scrolls into view.
6. `curl -sI <preview-url>/ | grep -i content-security-policy` must show hashes
   in `script-src`, no `'unsafe-inline'` in `script-src`/`style-src`, and the
   line must be under 2,000 characters.

Locally, the same checks can be run with
`cd website && npm ci && npm run build`, serving `dist/` with a server that
applies `dist/_headers` (plain `astro preview` does **not** send `_headers`).

## Migrating off GitHub Pages

GitHub Pages broke behind the Cloudflare proxy (GitHub's ACME validation couldn't
complete → `bad_authz` → Cloudflare returned HTTP 526). After the Cloudflare Pages
custom domain is live:

- In GitHub → Settings → Pages, remove the custom domain / disable the Pages site
  so the two don't fight over the domain.
- The old `website/public/CNAME` marker and the GitHub Pages deploy workflow were
  removed as part of this migration.
