# Containerized Agent-Development Starter Kit

A ready-to-adapt implementation of
[arch-09_containerized_agent_dev_standards.md](../../standards/architecture/arch-09_containerized_agent_dev_standards.md):
a reproducible Docker environment that gives AI coding agents (Claude Code,
Gemini CLI, Cursor, Antigravity) broad execution permissions inside a container,
with the scaffolding needed to bound that container's blast radius — including a
working deny-by-default egress proxy.

> These are **templates**, not a turnkey product. Install them into a consumer
> project (`.standards/scripts/setup.sh --containerized`), pin tool versions,
> adapt the language toolchain, and populate the whitelists. Then validate
> against the Definition of Done in arch-09 §8 — the kit is not arch-09
> compliant until that checklist passes on your host.

## What the kit enforces — and what it does not

Be precise about the security posture before trusting it:

| Control (arch-09) | Status out of the box |
|-------------------|-----------------------|
| Non-root dev user, scoped sudo (§2) | Enforced by `Dockerfile.dev` |
| Workspace as a volume, disposable image (§3) | Enforced by the compose file |
| **Deny-by-default egress (§4)** | **Enforced** for running containers. `devnet` is an `internal: true` network with no route to the internet; the only way out is the `egress` sidecar (tinyproxy), which refuses every destination not in `proxy/allowlist.generated.txt` and refuses to *start* without a valid allow-list. See [How egress enforcement works](#how-egress-enforcement-works) for what is and is not covered |
| No secrets baked into layers; `.env.secret` must be git-ignored (§5) | Enforced — `init-workspace.sh` refuses to write an un-ignored secret file |
| YOLO permissions live only in the image (§6) | Enforced by `Dockerfile.dev` |
| Container writes, host executes | **Inverted mount model:** the entire host checkout is read-only in `dev`, including future paths, standards fallbacks, submodule gitfiles and agent/MCP configs. Only Docker-owned caches are writable by default. Explicit source overlays require an audit; host MCP configs are never imported from the workspace. See [Threat model](#threat-model-what-the-agent-can-and-cannot-change) |
| Host Docker socket | **Not mounted.** Opt-in, commented out in the compose file with the trade-off spelled out; enabling it hands the container root-equivalent control of the host **and a path around the egress proxy** |
| Zed over SSH (§7) | Opt-in: `bootstrap-zed.sh` preflights for sshd and a published port and refuses to configure anything until both opt-in blocks are enabled |

## Contents

| File | Purpose | arch-09 |
|------|---------|---------|
| `Dockerfile.dev.example` | Full-toolchain dev image (base pinned by digest, Node 24 LTS, AI CLIs pinned by version), non-root sudo user (proxy variables survive `sudo`), `claude`/`gemini` YOLO shims on `PATH` | §1, §2, §3, §6 |
| `Dockerfile.prod.example` | Multi-stage → distroless, no shell, non-root | §1 |
| `Dockerfile.egress.example` | Egress-proxy sidecar image: Alpine + tinyproxy, unprivileged, config baked in, fail-closed entrypoint | §4 |
| `docker-compose.dev.yml.example` | Wires the internal network, the egress sidecar, read-only host workspace with optional source overlays, identity, secrets, proxy pointer (both env-var cases, plus `GIT_SSH_COMMAND`); Docker socket and SSH port are commented opt-ins | §3, §4, §5 |
| `scripts/init-workspace.sh.example` | Entry point: identity forwarding, secret capture; rewrites only its own keys in `.env`; runs no `git` (it executes on the host) | §5 |
| `scripts/setup-proxy.sh.example` | Validates (lowercase hostnames of two or more labels, optional `*.`) and combines the dual-layer whitelist into `proxy/allowlist.generated.txt`, the file the sidecar enforces; writes `EGRESS_PROXY*` and `NO_PROXY` to `.env` | §4 |
| `scripts/bootstrap-zed.sh.example` | Headless Zed remote over SSH (requires the sshd + port opt-ins; preflights both) | §7 |
| `scripts/bootstrap-antigravity.sh.example` | Register container with Antigravity Agent Manager; never imports workspace MCP commands into host settings | §7 |
| `network/global-whitelist.txt` | Baseline egress allow-list (ships with standards) | §4 |
| `proxy/project-whitelist.txt` | Project-specific egress allow-list | §4 |
| `proxy/tinyproxy.conf` | Sidecar config, baked into the image: deny by default, whole-host glob matching, CONNECT to 443/22 only, logs to stdout | §4 |
| `proxy/egress-entrypoint.sh` | Sidecar entrypoint + health check: asserts the deny-by-default config and refuses to start on a missing, empty or malformed allow-list (any glob other than a leading `*.`, single-label wildcards, URLs, upper case) | §4 |
| `.devcontainer/devcontainer.json` | VS Code Dev Containers integration (runs both setup scripts on the host first; the whole checkout and all their inputs are read-only in the sandbox) | §7 |
| `cursorrules.example` | Cursor "run in container" rules; installed as `.cursor/rules/containerized-dev.mdc` when Cursor is a configured agent | §7 |
| `env.secret.example` | Shape of the git-ignored runtime secret file | §5 |

## Install

From the consumer project root, with the standards installed at `.standards/`
(the layout `install.sh` and `setup.sh` produce):

```bash
.standards/scripts/setup.sh --containerized            # add --dry-run to preview every write
```

This copies the kit in with the `.example` suffix stripped — `Dockerfile.dev`,
`Dockerfile.prod`, `Dockerfile.egress`, `docker-compose.dev.yml`, `scripts/*.sh`
(made executable), `proxy/` (project whitelist, tinyproxy config, entrypoint),
`.devcontainer/devcontainer.json` and, when Cursor is among the configured
agents, `.cursor/rules/containerized-dev.mdc` — and adds `.env` and `.env.secret`
to `.gitignore` (P0, arch-09 §5); it refuses to run while either file is already
tracked, since ignoring a tracked file does not untrack it (`git rm --cached`
first). It follows the safe-setup rules: an existing
file is never overwritten; one that differs from the kit is kept and the kit's
version is staged to `.standards-pending/<path>` with a note in `MERGE_PLAN.md`
(`/merge-standards` or `make merge-standards` walks you through it). Kit files
are yours to adapt, so they are not checksum-tracked and `sync-standards` never
touches them. The global whitelist (`network/global-whitelist.txt`) stays in the
standards checkout, where `setup-proxy.sh` reads it: `.standards/` first, then
`coding_standards/`, or `GLOBAL_WHITELIST=<path>`. When neither directory is in
the project (setup run from a clone of the standards repo), setup snapshots it to
`proxy/global-whitelist.txt`, which `setup-proxy.sh` falls back to; re-run
`--containerized` after updating the standards to stage a newer copy. Without the
flag, `setup.sh` only prints how to install the kit.

Installing by hand, with the standards vendored at `coding_standards/`:

```bash
# From the consumer project root
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
git submodule update --init --recursive                  # once, on the host, after reviewing .gitmodules
./scripts/init-workspace.sh                              # identity + secrets (no git — see threat model)
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

On macOS the host's `SSH_AUTH_SOCK` path does not exist inside the Docker VM, so
`init-workspace.sh` writes the VM-side path `/run/host-services/ssh-auth.sock`
to `.env` as `SSH_AGENT_SOURCE` instead (Docker Desktop forwards the agent
there; Colima only when started with `colima start --ssh-agent`; override with
`CONTAINER_SSH_AUTH_SOCK`). The mount source has its own key because compose
lets the calling shell's environment override `.env`, and every macOS shell
exports `SSH_AUTH_SOCK`. Without a forwarded agent `ssh-add -l` inside the
container reports "Permission denied" and git over SSH needs a token or HTTPS —
everything else still works.

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

**Chosen design (#221): invert the mount model.** The entire host checkout is
mounted read-only at `/workspace`. There is no list of protected files to keep
extending: an absent `.standards/`, `.antigravity/mcp.json`, or nested `.git`
created later by the host is covered automatically. The container has no
`CAP_SYS_ADMIN`, so container `sudo` cannot remount that bind writable.

| Host-side consumer | Inputs | Protection |
|--------------------|--------|------------|
| Container writes, host executes | Every current and future checkout path | Read-only root bind; writable named caches have no host-checkout backing path |
| `initializeCommand` | `scripts/`, `.devcontainer/`, `.gitignore`, `.env*` | Read-only root; setup scripts never invoke host git |
| `setup-proxy.sh` | Global lists in `.standards/`, `coding_standards/` or `proxy/`; project list in `proxy/` | All fallbacks and their parent directories are read-only; the agent cannot create an earlier-priority fallback |
| Antigravity bootstrap | Container registration only | Never copies or merges workspace MCP definitions into host settings; install host servers separately from a reviewed source |
| Host git and submodule auto-detection | Entire `.git`, submodule working trees and `.git` gitfiles, `.gitmodules` | All read-only, including file replacement and nested `.git` creation; no kit host script runs git |
| IDEs, task runners, image builds | `.claude/`, `.antigravity/`, `.vscode/`, `Makefile`, `package.json`, all Dockerfiles and compose inputs | Read-only root; any additional host consumer is protected without another mount entry |

### Editable sources and commits

The shipped default is a read-only reference checkout. Builds write to named
caches or a container-owned directory, not to the host checkout. For ordinary
branch/commit work, make a **fresh clone of the reviewed remote URL** inside the
container-owned `dev-cache` volume, for example
`git clone <reviewed-remote-url> /home/developer/.cache/project`, then open that
folder in the attached IDE. If the cache volume is initially root-owned, first
run `sudo chown "$(id -u):$(id -g)" /home/developer/.cache` inside the container.
Work, checkpoint, commit and push from that clone.
Do not copy host `.git` metadata or make the host `.git` writable. The clone
survives container rebuilds; `docker compose down -v` deletes it, so push work
before removing volumes. Host tooling must never execute this clone or consume
its configs, hooks, MCP commands or allow-lists. Builds in that clone run inside
the sandbox. The host checkout receives changes only through reviewed Git work.

For projects that need host-visible source edits, the compose template has
**commented examples** for `src/` and `tests/` overlays. Declare only the source
directories required by the task, with `create_host_path: false`; keep all their
ancestors read-only. Never overlay infrastructure, standards, `.git`, proxy or
IDE/agent configuration directories. An overlay grants write access to **every**
descendant, including newly created scripts and `.git` files. Consequently no
host-side script, git auto-detection, IDE task, MCP server or image build may
consume an overlay before human review. Run source builds/tests in the sandbox.
Root manifests and git metadata remain read-only; use the container-owned clone
when a task needs to change them.

`scripts/check-container-host-boundary.sh` guards the shipped mount contract in
`make test-containerized-dev`: it rejects a writable root, unknown mount syntax
and every undeclared writable bind. The regression tests inject writable mounts
for each former gap plus an unknown future host input and require rejection.
When Docker is available, the suite also checks that container root cannot
write those inputs, create a new host path, or replace a submodule gitfile through
a read-only bind. Without a daemon this check is explicitly skipped.
A project enabling an overlay must update its guard policy only after auditing
all host consumers of that directory; it cannot claim the shipped guarantee
merely because the template once passed.

### Upgrading an existing installation

Stop the old dev container first. Run `setup.sh --containerized` from a reviewed
standards checkout **on the host**, then reconcile the staged compose, bootstrap
and Dev Containers files with this model. Setup keeps your existing kit files;
staging an update does not secure a still-running writable sandbox. Remove the
old writable root mount, recreate the dev service, and verify its effective
mounts and write-denial checks below. Do not copy an old workspace MCP config
into host settings. Review any host config, allow-list or submodule metadata
that an earlier container could have changed before reusing it.

Still outside the model: the Docker socket opt-in (root-equivalent host control),
host commands deliberately run against unreviewed source overlays, and image
builds from agent-modified sources (they run outside the egress network). A
read-only mount protects against container writes, not a human accepting an
untrusted change on the host.

Using a different enforcing proxy (a corporate egress gateway, Squid with its own
ACLs)? Point `EGRESS_PROXY` at it when running `setup-proxy.sh`, remove the
`egress` service and the `depends_on` from the compose file, and keep `devnet`
internal **only if** that proxy is reachable from it. Otherwise you are back to
a hint, not a control — and the deny-path check below will tell you so.

## Validate (Definition of Done — arch-09 §8)

```bash
# 1. Agents run without permission prompts: the shims on PATH carry the flags
#    (expect /usr/local/bin/claude and /usr/local/bin/gemini, each exec-ing the
#    real binary with --dangerously-skip-permissions / --yolo)
docker compose -f docker-compose.dev.yml exec dev bash -lc 'command -v claude gemini; cat "$(command -v claude)"; claude --version && gemini --version && ls'
#    Authenticating the CLIs is interactive (`claude` login, `gemini` login) unless
#    ANTHROPIC_API_KEY / GEMINI_API_KEY were captured into .env.secret.

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

# 2d. Every write MUST fail, including sudo and paths missing on the host.
docker compose -f docker-compose.dev.yml exec dev sh -c 'for p in scripts/x proxy/x .git/hooks/x .env .standards/x coding_standards/.git .antigravity/mcp.json Makefile; do touch "$p" 2>&1; sudo touch "$p" 2>&1; done; mkdir /workspace/new-host-input 2>&1; git config core.hooksPath /tmp 2>&1'
# In the container-owned clone, normal source edits and git commits MUST work.

# 3. An allowed host works (expect 200), also through sudo (env_keep) and from Node
#    (NODE_USE_ENV_PROXY=1 in the compose file; without it fetch() fails with EAI_AGAIN)
docker compose -f docker-compose.dev.yml exec dev curl -sS --max-time 10 -o /dev/null -w '%{http_code}\n' https://api.github.com
docker compose -f docker-compose.dev.yml exec dev sudo curl -sS --max-time 10 -o /dev/null -w '%{http_code}\n' https://registry.npmjs.org/
docker compose -f docker-compose.dev.yml exec dev node -e 'fetch("https://api.github.com").then(r => console.log(r.status))'

# 4. The proxy logged both verdicts
docker compose -f docker-compose.dev.yml logs egress | grep -E 'malicious-site.com|api.github.com'

# 5. No host Docker socket, no added capabilities, egress unprivileged and unpublished
docker inspect "$(docker compose -f docker-compose.dev.yml ps -q dev)" --format '{{json .Mounts}}' | grep -c docker.sock   # expect 0
docker inspect "$(docker compose -f docker-compose.dev.yml ps -q dev)" --format 'Privileged={{.HostConfig.Privileged}} CapAdd={{.HostConfig.CapAdd}} User={{.Config.User}}'
docker inspect "$(docker compose -f docker-compose.dev.yml ps -q egress)" --format 'ports={{json .NetworkSettings.Ports}} user={{.Config.User}}'
```

A complete run of this list against a real Docker host, with the output observed
and the kit fixes it produced, is recorded in the standards repo at
[`docs/guides/containerized-dev-validation.md`](../../docs/guides/containerized-dev-validation.md).
Use it as the model for your own record: every DoD item names the command, the
verdict and what was *not* verified (IDE connections and CLI logins are
interactive and stay manual).
