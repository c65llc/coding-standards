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

## Migrating off GitHub Pages

GitHub Pages broke behind the Cloudflare proxy (GitHub's ACME validation couldn't
complete → `bad_authz` → Cloudflare returned HTTP 526). After the Cloudflare Pages
custom domain is live:

- In GitHub → Settings → Pages, remove the custom domain / disable the Pages site
  so the two don't fight over the domain.
- The old `website/public/CNAME` marker and the GitHub Pages deploy workflow were
  removed as part of this migration.
