# Containerized Agent-Development Starter Kit

A ready-to-adapt implementation of
[arch-09_containerized_agent_dev_standards.md](../../standards/architecture/arch-09_containerized_agent_dev_standards.md):
a reproducible Docker environment that gives AI coding agents (Claude Code,
Gemini CLI, Cursor, Antigravity) broad execution permissions inside a container,
with the scaffolding needed to bound that container's blast radius — including a
working deny-by-default egress proxy.

> These are **templates**, not a turnkey product. Copy them into a consumer
> project, pin tool versions, adapt the language toolchain, and populate the
> whitelists. Then validate against the Definition of Done in arch-09 §8 —
> the kit is not arch-09 compliant until that checklist passes on your host.

## What the kit enforces — and what it does not

Be precise about the security posture before trusting it:

| Control (arch-09) | Status out of the box |
|-------------------|-----------------------|
| Non-root dev user, scoped sudo (§2) | Enforced by `Dockerfile.dev` |
| Workspace as a volume, disposable image (§3) | Enforced by the compose file |
| **Deny-by-default egress (§4)** | **Enforced** for running containers. `devnet` is an `internal: true` network with no route to the internet; the only way out is the `egress` sidecar (tinyproxy), which refuses every destination not in `proxy/allowlist.generated.txt` and refuses to *start* without a valid allow-list. See [How egress enforcement works](#how-egress-enforcement-works) for what is and is not covered |
| No secrets baked into layers; `.env.secret` must be git-ignored (§5) | Enforced — `init-workspace.sh` refuses to write an un-ignored secret file |
| YOLO permissions live only in the image (§6) | Enforced by `Dockerfile.dev` |
| Host Docker socket | **Not mounted.** Opt-in, commented out in the compose file with the trade-off spelled out; enabling it hands the container root-equivalent control of the host **and a path around the egress proxy** |
| Zed over SSH (§7) | Opt-in: `bootstrap-zed.sh` preflights for sshd and a published port and refuses to configure anything until both opt-in blocks are enabled |

## Contents

| File | Purpose | arch-09 |
|------|---------|---------|
| `Dockerfile.dev.example` | Full-toolchain dev image, non-root sudo user (proxy variables survive `sudo`), baked YOLO agent config | §1, §2, §6 |
| `Dockerfile.prod.example` | Multi-stage → distroless, no shell, non-root | §1 |
| `Dockerfile.egress.example` | Egress-proxy sidecar image: Alpine + tinyproxy, unprivileged, fail-closed entrypoint | §4 |
| `docker-compose.dev.yml.example` | Wires the internal network, the egress sidecar, workspace volume, identity, secrets, proxy pointer (both env-var cases, plus `GIT_SSH_COMMAND`); Docker socket and SSH port are commented opt-ins | §3, §4, §5 |
| `scripts/init-workspace.sh.example` | Entry point: identity forwarding, secret capture, submodule sync; rewrites only its own keys in `.env` | §5 |
| `scripts/setup-proxy.sh.example` | Validates and combines the dual-layer whitelist into `proxy/allowlist.generated.txt`, the file the sidecar enforces; writes `EGRESS_PROXY*` and `NO_PROXY` to `.env` | §4 |
| `scripts/bootstrap-zed.sh.example` | Headless Zed remote over SSH (requires the sshd + port opt-ins; preflights both) | §7 |
| `scripts/bootstrap-antigravity.sh.example` | Register container with Antigravity Agent Manager; merges, never overwrites, an existing MCP config | §7 |
| `network/global-whitelist.txt` | Baseline egress allow-list (ships with standards) | §4 |
| `proxy/project-whitelist.txt` | Project-specific egress allow-list | §4 |
| `proxy/tinyproxy.conf` | Sidecar config: deny by default, whole-host glob matching, CONNECT to 443/22 only, logs to stdout | §4 |
| `proxy/egress-entrypoint.sh` | Sidecar entrypoint + health check: refuses to start on a missing, empty or catch-all allow-list | §4 |
| `.devcontainer/devcontainer.json` | VS Code Dev Containers integration (runs both setup scripts first) | §7 |
| `cursorrules.example` | Cursor "run in container" rules | §7 |
| `env.secret.example` | Shape of the git-ignored runtime secret file | §5 |

## Install

```bash
# From the consumer project root, with these standards vendored at coding_standards/
cp coding_standards/templates/containerized-dev/Dockerfile.dev.example        Dockerfile.dev
cp coding_standards/templates/containerized-dev/Dockerfile.prod.example       Dockerfile.prod
cp coding_standards/templates/containerized-dev/Dockerfile.egress.example     Dockerfile.egress
cp coding_standards/templates/containerized-dev/docker-compose.dev.yml.example docker-compose.dev.yml
mkdir -p scripts proxy .devcontainer
cp coding_standards/templates/containerized-dev/scripts/*.example             scripts/
for f in scripts/*.example; do mv "$f" "${f%.example}"; chmod +x "${f%.example}"; done
cp -R coding_standards/templates/containerized-dev/proxy/.                    proxy/
cp coding_standards/templates/containerized-dev/.devcontainer/devcontainer.json .devcontainer/

# Never commit secrets — ignore the generated files first (P0, arch-09 §5).
# The generated allow-list may be committed or ignored; either way, regenerate it.
printf '\n.env\n.env.secret\nproxy/allowlist.generated.txt\n' >> .gitignore
```

## Run

```bash
./scripts/init-workspace.sh                              # identity + secrets + submodules
./scripts/setup-proxy.sh                                 # validate + generate proxy/allowlist.generated.txt
docker compose -f docker-compose.dev.yml up -d --build   # egress sidecar first, then dev
docker compose -f docker-compose.dev.yml exec dev bash   # drop into the container
```

Re-running either script is safe: `init-workspace.sh` and `setup-proxy.sh` each
rewrite only the `.env` keys they own and leave every other line alone. After
changing a whitelist, re-run `setup-proxy.sh` and then
`docker compose -f docker-compose.dev.yml restart egress` — tinyproxy reads the
allow-list once, at start-up.

## How egress enforcement works

```text
                 devnet (internal: true — no route out)        egressnet (internet)
  ┌─────────┐    *_PROXY=http://egress:3128     ┌────────────┐
  │   dev   │ ───────────────────────────────▶  │   egress   │ ──▶ allowed host   (200)
  │ (agent) │   direct attempt ──▶ ✗ no route   │ tinyproxy  │ ──▶ unlisted host  (403, never dialled)
  └─────────┘                                   └────────────┘
```

* **Two networks.** `dev` is only on `devnet`, which Docker marks `internal`:
  packets to anything outside the network are dropped. `egress` is on both
  `devnet` and `egressnet`; it is the only thing with an internet route.
* **Proxy variables are a pointer, not the control.** `HTTP_PROXY`/`HTTPS_PROXY`
  (and lowercase, because tools disagree) tell cooperative tools where the proxy
  is. A process that ignores or unsets them does not "go direct" — it gets no
  connection at all. `sudo` keeps the proxy variables (`env_keep` in
  `Dockerfile.dev`) so `sudo apt-get install` works through the proxy.
* **`NO_PROXY` is a bypass list, not an allow-list.** It names hosts tools reach
  *directly* on `devnet` instead of via the proxy: loopback, and any in-compose
  service you add (`NO_PROXY_BYPASS=localhost,127.0.0.1,::1,db,redis`). A public
  host listed there is not reachable at all, because `devnet` has no route to it.
* **The allow-list is the proxy's filter.** `setup-proxy.sh` rejects anything
  that is not a hostname (optionally `*.`-prefixed for all subdomains), so a
  stray `*` or URL cannot widen it, and tinyproxy matches each entry as a
  whole-host glob with `FilterDefaultDeny`: `github.com` does not match
  `github.com.evil.example`. Unlisted hosts get a 403 before any upstream
  connection is made; every verdict is in `docker compose logs egress`.
* **Fails closed.** `egress-entrypoint.sh` refuses to start when the allow-list
  is missing (Docker would mount a directory), empty or contains a bare `*`,
  and `dev` waits for `egress` to be healthy — so a broken allow-list stops the
  environment instead of opening it.
* **Git over SSH is tunnelled, not exempted.** SSH has no proxy variables, so the
  compose file sets `GIT_SSH_COMMAND` to a CONNECT `ProxyCommand` (`nc -X
  connect`, from `netcat-openbsd`) and `tinyproxy.conf` permits CONNECT to port
  22 as well as 443. The git host still has to be on the allow-list.

What it does **not** cover — know these before calling the environment contained:

* **Image builds.** `docker compose build` runs on the Docker host network, not
  `devnet`. Build steps can reach anything; keep them to pinned, reviewed sources
  (arch-09 §3). Only running containers are filtered.
* **TLS contents.** The proxy sees the destination host of a CONNECT tunnel, not
  the URL, so an allowed host is allowed for every path on it. Prefer exact hosts
  over `*.` wildcards; every entry widens the exfiltration surface.
* **The egress sidecar itself.** It has unrestricted internet access by design.
  Never add `ports:` to it (that makes it an open proxy for your LAN), and never
  put anything but the proxy on `egressnet`.
* **Opt-ins that bypass the network.** Mounting the host Docker socket lets the
  container start workloads outside `devnet`. The SSH port opt-in publishes a
  port *into* the sandbox only; it does not open a way out.
* **DNS is not the control either.** On an internal network Docker's embedded
  resolver typically does not forward external lookups, so a direct request
  fails with "Could not resolve host" — but do not rely on that. The deny-path
  checks below test the *connection*, which is what matters.

Using a different enforcing proxy (a corporate egress gateway, Squid with its own
ACLs)? Point `EGRESS_PROXY` at it when running `setup-proxy.sh`, remove the
`egress` service and the `depends_on` from the compose file, and keep `devnet`
internal **only if** that proxy is reachable from it. Otherwise you are back to
a hint, not a control — and the deny-path check below will tell you so.

## Validate (Definition of Done — arch-09 §8)

```bash
# 1. Agents run without permission prompts
docker compose -f docker-compose.dev.yml exec dev bash -lc 'claude --version && gemini --version && ls'

# 2. Egress deny path works — this MUST fail (tinyproxy answers 403 and never
#    dials out). If it succeeds, egress is NOT contained and the DoD is not met.
docker compose -f docker-compose.dev.yml exec dev curl -sS --max-time 10 https://malicious-site.com && \
  echo "FAIL: unlisted host was reachable" || echo "OK: unlisted host blocked"

# 2b. ...and bypassing the proxy variables changes nothing — the network, not the
#     environment, is the control. This MUST fail too (no route from devnet).
docker compose -f docker-compose.dev.yml exec dev curl -sS --max-time 10 --noproxy '*' https://api.github.com && \
  echo "FAIL: direct egress possible" || echo "OK: direct egress blocked"

# 3. An allowed host works (expect 200)
docker compose -f docker-compose.dev.yml exec dev curl -sS --max-time 10 -o /dev/null -w '%{http_code}\n' https://api.github.com

# 4. The proxy logged both verdicts
docker compose -f docker-compose.dev.yml logs egress | grep -E 'malicious-site.com|api.github.com'
```
