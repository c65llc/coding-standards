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
| Host-executed files protected from the sandbox | **Enforced** by the compose file: `scripts/`, `proxy/`, `.devcontainer/`, the Dockerfiles and the compose file are mounted read-only into `dev`, so an agent cannot plant code the host runs (`initializeCommand`, `compose up --build`) or widen the proxy for the next start. See [Threat model](#threat-model-what-the-agent-can-and-cannot-change) |
| Host Docker socket | **Not mounted.** Opt-in, commented out in the compose file with the trade-off spelled out; enabling it hands the container root-equivalent control of the host **and a path around the egress proxy** |
| Zed over SSH (§7) | Opt-in: `bootstrap-zed.sh` preflights for sshd and a published port and refuses to configure anything until both opt-in blocks are enabled |

## Contents

| File | Purpose | arch-09 |
|------|---------|---------|
| `Dockerfile.dev.example` | Full-toolchain dev image, non-root sudo user (proxy variables survive `sudo`), baked YOLO agent config | §1, §2, §6 |
| `Dockerfile.prod.example` | Multi-stage → distroless, no shell, non-root | §1 |
| `Dockerfile.egress.example` | Egress-proxy sidecar image: Alpine + tinyproxy, unprivileged, config baked in, fail-closed entrypoint | §4 |
| `docker-compose.dev.yml.example` | Wires the internal network, the egress sidecar, workspace volume (host-executed files read-only), identity, secrets, proxy pointer (both env-var cases, plus `GIT_SSH_COMMAND`); Docker socket and SSH port are commented opt-ins | §3, §4, §5 |
| `scripts/init-workspace.sh.example` | Entry point: identity forwarding, secret capture, submodule sync; rewrites only its own keys in `.env` | §5 |
| `scripts/setup-proxy.sh.example` | Validates (lowercase hostnames of two or more labels, optional `*.`) and combines the dual-layer whitelist into `proxy/allowlist.generated.txt`, the file the sidecar enforces; writes `EGRESS_PROXY*` and `NO_PROXY` to `.env` | §4 |
| `scripts/bootstrap-zed.sh.example` | Headless Zed remote over SSH (requires the sshd + port opt-ins; preflights both) | §7 |
| `scripts/bootstrap-antigravity.sh.example` | Register container with Antigravity Agent Manager; merges, never overwrites, an existing MCP config | §7 |
| `network/global-whitelist.txt` | Baseline egress allow-list (ships with standards) | §4 |
| `proxy/project-whitelist.txt` | Project-specific egress allow-list | §4 |
| `proxy/tinyproxy.conf` | Sidecar config, baked into the image: deny by default, whole-host glob matching, CONNECT to 443/22 only, logs to stdout | §4 |
| `proxy/egress-entrypoint.sh` | Sidecar entrypoint + health check: asserts the deny-by-default config and refuses to start on a missing, empty or malformed allow-list (any glob other than a leading `*.`, single-label wildcards, URLs, upper case) | §4 |
| `.devcontainer/devcontainer.json` | VS Code Dev Containers integration (runs both setup scripts on the host first; they are read-only in the sandbox) | §7 |
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

Run `setup-proxy.sh` **before** the first `compose up`: the allow-list mount is
declared with `create_host_path: false`, so a missing file fails `compose up` with
a clear error instead of silently creating a directory in its place.

Re-running either script is safe: `init-workspace.sh` and `setup-proxy.sh` each
rewrite only the `.env` keys they own and leave every other line alone. After
changing a whitelist, re-run `setup-proxy.sh` and then
`docker compose -f docker-compose.dev.yml restart egress` — tinyproxy reads the
allow-list once, at start-up. After changing `proxy/tinyproxy.conf` or
`proxy/egress-entrypoint.sh`, rebuild: `docker compose -f docker-compose.dev.yml
up -d --build egress` (both are part of the image, not mounts). All of this
happens on the host — see the threat model below for why.

Requires Docker Engine 26.0 or later (or 25.0.5+): earlier engines forwarded
external DNS lookups from internal networks when the host used a loopback
resolver ([CVE-2024-29018](https://github.com/moby/moby/security/advisories/GHSA-mq39-4gv4-mvpx)),
which turns DNS labels into an exfiltration channel the HTTP checks cannot see.
Check with `docker version --format '{{.Server.Version}}'` and run the DNS deny
check in [Validate](#validate-definition-of-done--arch-09-8).

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
* **The allow-list is the proxy's filter.** `setup-proxy.sh` lowercases every
  entry and rejects anything that is not a hostname of two or more labels
  (optionally `*.`-prefixed for all subdomains), so a stray `*`, `*.com`, URL or
  path cannot widen it, and tinyproxy matches each entry as a whole-host glob
  with `FilterDefaultDeny`: `github.com` does not match `github.com.evil.example`.
  Matching is case-sensitive (`fnmatch`), which is why entries are normalised —
  a client spelling an allowed host in upper case is denied, never let through.
  Unlisted hosts get a 403 before any upstream connection is made; every verdict
  is in `docker compose logs egress`.
* **Fails closed.** `egress-entrypoint.sh` trusts nothing it is handed: it
  asserts that the baked-in config still carries `FilterDefaultDeny Yes`,
  `FilterType fnmatch`, `FilterURLs Off` and exactly one `Filter` line pointing
  at the mounted allow-list, and has no `Upstream`/`Reverse*` directive; then it
  re-validates every allow-list entry against the same grammar `setup-proxy.sh`
  uses. A missing, empty, hand-edited or stale allow-list, or an edited config,
  stops the sidecar — and `dev` waits for `egress` to be healthy, so a broken
  allow-list halts the environment instead of opening it.
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
* **DNS is a channel of its own.** On an internal network Docker's embedded
  resolver must not forward external lookups (a direct request fails with
  "Could not resolve host"). Engines affected by CVE-2024-29018 did forward them
  when the host ran a loopback resolver, and a forwarded lookup for
  `<secret>.attacker.example` exfiltrates data without any connection being
  made. Require a patched engine and run the DNS deny check below; the HTTP
  checks alone cannot detect this.

## Threat model: what the agent can and cannot change

The agent runs with broad permissions and `sudo` inside `dev`, and the whole
project is bind-mounted at `/workspace`. Several files in that project are
executed or consumed **by the host**, which would hand an agent host code
execution on the next start if it could edit them:

| Host-side consumer | Files | Protection |
|--------------------|-------|------------|
| `devcontainer.json` `initializeCommand` (runs on the host) | `scripts/init-workspace.sh`, `scripts/setup-proxy.sh`, `.devcontainer/` | mounted read-only into `dev` |
| `docker compose up --build` (host daemon) | `docker-compose.dev.yml`, `Dockerfile.dev`, `Dockerfile.egress` | mounted read-only into `dev` |
| egress sidecar enforcement | `proxy/` (whitelists, generated allow-list, `tinyproxy.conf`, entrypoint) | mounted read-only into `dev`; config baked into the image and asserted; every entry validated at start |

Nested read-only bind mounts take precedence over the writable workspace mount
for exactly those paths, and a container without `CAP_SYS_ADMIN` (the default)
cannot remount them — `sudo` inside the container does not help. Consequences:

* **Infrastructure is edited on the host, by a human.** Including the whitelists:
  widening egress is a reviewed, host-side change followed by `setup-proxy.sh`
  and an `egress` restart, never something the agent can do from inside.
* `git checkout`/`git pull` inside the container fails with "Read-only file
  system" if the incoming change touches a protected path. Pull such changes on
  the host.
* The global whitelist lives in the standards submodule (`coding_standards/`),
  which is *writable* in the container; the entrypoint's validation means an
  agent editing it can add hostnames but never a catch-all, and the change only
  takes effect after a human re-runs `setup-proxy.sh` on the host and restarts
  the sidecar — review `git diff coding_standards/` before doing so, or mount
  that directory read-only too if the agent never needs to sync standards.

Still outside the model: the Docker socket opt-in (root-equivalent host control),
and anything the host operator runs by hand from the workspace.

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
#    --fail matters: for plain http:// curl exits 0 on a 403 without it.
docker compose -f docker-compose.dev.yml exec dev curl -sS --fail --max-time 10 https://malicious-site.com && \
  echo "FAIL: unlisted host was reachable" || echo "OK: unlisted host blocked"
docker compose -f docker-compose.dev.yml exec dev curl -sS --fail --max-time 10 http://malicious-site.com && \
  echo "FAIL: unlisted host was reachable" || echo "OK: unlisted host blocked"

# 2b. ...and bypassing the proxy variables changes nothing — the network, not the
#     environment, is the control. This MUST fail too (no route from devnet).
docker compose -f docker-compose.dev.yml exec dev curl -sS --fail --max-time 10 --noproxy '*' https://api.github.com && \
  echo "FAIL: direct egress possible" || echo "OK: direct egress blocked"

# 2c. ...and DNS does not leak either: an external lookup from devnet MUST fail
#     (CVE-2024-29018 engines forward it, which exfiltrates data in the name).
docker compose -f docker-compose.dev.yml exec dev getent hosts dns-leak-check.example.com && \
  echo "FAIL: external DNS resolves from devnet — upgrade Docker Engine" || echo "OK: external DNS blocked"

# 2d. ...and the sandbox cannot rewrite what the host runs (expect "Read-only file system")
docker compose -f docker-compose.dev.yml exec dev sh -c 'touch scripts/x proxy/x 2>&1; sudo touch scripts/x 2>&1'

# 3. An allowed host works (expect 200)
docker compose -f docker-compose.dev.yml exec dev curl -sS --max-time 10 -o /dev/null -w '%{http_code}\n' https://api.github.com

# 4. The proxy logged both verdicts
docker compose -f docker-compose.dev.yml logs egress | grep -E 'malicious-site.com|api.github.com'
```
