# Deployment — Cloudflare Pages

The documentation site (`website/`, Astro + Starlight) is a fully static build
deployed to **Cloudflare Pages**. This file is a maintainer runbook; it is not
published to the site.

## How CI deploys

`.github/workflows/deploy.yml` publishes **only** when:

- a **GitHub Release is published** (`release: [published]`) — i.e. when we cut a
  release; or
- a **blog post is added/edited** on `main` (`push` to `website/src/content/docs/blog/**`); or
- it is run **manually** (`workflow_dispatch`).

Routine docs/standards changes merged to `main` do **not** trigger a publish.
When it does run it:

1. Build the Astro site (`cd website && npm run build` → `website/dist`).
2. `cloudflare/wrangler-action` runs `wrangler pages deploy --branch=main` from
   `website/`, which reads the project name and output dir from
   [`website/wrangler.jsonc`](../website/wrangler.jsonc).

`--branch=main` produces a **production** deployment (the project's production
branch must be `main`); any other branch would be a preview deployment.

## One-time setup (manual — needs Cloudflare dashboard / an authed `wrangler`)

These steps are done once by a maintainer with Cloudflare access; CI cannot do
them because they need account-level + DNS permissions.

1. **Create the Pages project** (name must match `wrangler.jsonc` → `coding-standards`):

   ```sh
   cd website
   npx wrangler pages project create coding-standards --production-branch=main
   ```

   (or create it in the Cloudflare dashboard → Workers & Pages → Create → Pages).

2. **Add the CI secrets** to the GitHub repo (Settings → Secrets and variables → Actions):
   - `CLOUDFLARE_API_TOKEN` — a token with the **Account › Cloudflare Pages › Edit** permission.
   - `CLOUDFLARE_ACCOUNT_ID` — the Cloudflare account ID.

3. **Attach the custom domain.** In the Pages project → Custom domains → add
   `coding-standards.c65llc.com`. Because DNS is already on Cloudflare, this is
   one click and Cloudflare issues/manages the TLS certificate automatically —
   no cross-provider cert dance.

4. **Point DNS at Pages.** Cloudflare creates/updates the `coding-standards`
   CNAME to the `*.pages.dev` target automatically when you add the custom
   domain above. The record stays **proxied (orange cloud)** and SSL just works
   (no more HTTP 526).

## Migrating off GitHub Pages

This repo previously deployed to GitHub Pages, which broke behind the Cloudflare
proxy (GitHub's ACME validation couldn't complete → `bad_authz` → Cloudflare
returned HTTP 526). After the Cloudflare Pages custom domain is live:

- In GitHub → Settings → Pages, remove the custom domain / disable the Pages
  site so the two don't fight over the domain.
- The old `website/public/CNAME` marker and the GitHub Pages workflow have been
  removed in this migration.
