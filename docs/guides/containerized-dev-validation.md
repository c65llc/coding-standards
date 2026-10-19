---
title: "Containerized Dev Validation"
description: "Run the arch-09 Definition of Done against a real Docker host, and the dated record of the run that pinned the starter kit."
---

# Containerized Dev Validation

[arch-09](../../standards/architecture/arch-09_containerized_agent_dev_standards.md)
is explicit that a dev-container setup is compliant only when its Definition of
Done (§8) has been **observed** on a real Docker host — a request to an unlisted
domain actually fails, the agent CLIs actually run without prompts, no host
Docker socket is actually mounted. Reading the compose file is not evidence.

This guide has two parts. The first is the procedure: how to take the
[starter kit](../../templates/containerized-dev/README.md) from
`setup.sh --containerized` to a checked-off DoD on your own host, with the exact
commands and what each one must print. The second is the record of the run that
first did this (2026-10-19, #158), including the kit defects it found and fixed.
Keep your own record in the same shape — every item names the command, the
verdict, and what was *not* verified.

## Procedure

### 0. Host prerequisites

- Docker Engine **26.0 or later** (25.0.5+). Earlier engines forwarded external
  DNS from `internal: true` networks when the host used a loopback resolver
  ([CVE-2024-29018](https://github.com/moby/moby/security/advisories/GHSA-mq39-4gv4-mvpx)),
  turning DNS labels into an exfiltration channel the HTTP checks cannot see.
  Check: `docker version --format '{{.Server.Version}}'`.
- Docker Compose v2 (`docker compose version`).
- The project directory must be visible to the Docker daemon. On macOS the
  daemon runs in a VM that shares only certain paths (Docker Desktop: your home
  by default; Colima: `$HOME` and `/tmp/colima`). A project under `/private/tmp`
  or another unshared path mounts as an empty directory — `ls /workspace` inside
  the container is the first thing to check.

### 1. Install the kit into a consumer project

From the consumer project root, with the standards vendored at `.standards/`:

```bash
.standards/scripts/setup.sh --agents claude-code,cursor --containerized
```

Expected: one `✅ Installed` line per kit file (`Dockerfile.dev`,
`Dockerfile.egress`, `Dockerfile.prod`, `docker-compose.dev.yml`,
`scripts/{init-workspace,setup-proxy,bootstrap-zed,bootstrap-antigravity}.sh`,
`proxy/{egress-entrypoint.sh,project-whitelist.txt,tinyproxy.conf}`,
`.devcontainer/devcontainer.json`, `.cursor/rules/containerized-dev.mdc`) and
`✅ .env and .env.secret added to .gitignore`. Setup refuses to run while either
file is tracked.

### 2. Generate identity, secrets and the allow-list on the host

```bash
./scripts/init-workspace.sh      # writes .env (HOST_UID/GID, SSH_AGENT_SOURCE) and 0600 .env.secret
./scripts/setup-proxy.sh         # validates both whitelists → proxy/allowlist.generated.txt, proxy keys in .env
git check-ignore -v .env .env.secret   # both must match a .gitignore rule
```

`init-workspace.sh` captures `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`,
`GEMINI_API_KEY` and `GH_TOKEN` from the host environment if present and prints
only the variable *names* it captured. To see the `.gitignore` guard itself,
run it once in a scratch directory whose `.gitignore` lacks `.env.secret`: it
must exit 1 with `Refusing to write .env.secret: .gitignore does not list it.`
and create nothing.

### 3. Bring the stack up

```bash
docker compose -f docker-compose.dev.yml up -d --build
docker compose -f docker-compose.dev.yml ps
```

Expected order in the output: `egress` built and `Healthy`, then `dev` started.
`ps` shows `consumer-egress-1 ... (healthy) 3128/tcp` (a container port, not a
published one) and `consumer-dev-1 ... Up`. `docker compose logs egress` opens
with `egress: N allow-list entries loaded from /etc/tinyproxy/filter; every
other destination is denied.`

### 4. Run the Definition of Done

Run every block; the verdict column in your record is what each printed.

```bash
X="docker compose -f docker-compose.dev.yml exec -T dev"

# DoD 1 — agent CLIs run through the container shell, shims carry the YOLO flags
$X bash -lc 'command -v claude gemini; cat /usr/local/bin/claude; claude --version && gemini --version && ls'

# DoD 2 — egress deny path: every line MUST fail (curl exit 22 / 56, proxy answers 403)
$X curl -sS --fail --max-time 10 https://malicious-site.com
$X curl -sS --fail --max-time 10 http://malicious-site.com
$X curl -sS --fail --max-time 10 https://github.com.evil.example/      # suffix spoof of an allowed host
$X curl -sS --fail --max-time 10 --noproxy '*' https://api.github.com   # bypassing the proxy variables
$X getent hosts dns-leak-check.example.com                              # DNS from devnet (exit 2)

# DoD 2, allow path — expect 200, 200, "node fetch: 200"
$X curl -sS --max-time 10 -o /dev/null -w '%{http_code}\n' https://api.github.com
$X sudo -n curl -sS --max-time 10 -o /dev/null -w '%{http_code}\n' https://registry.npmjs.org/
$X node -e 'fetch("https://api.github.com").then(r => console.log("node fetch:", r.status))'
docker compose -f docker-compose.dev.yml logs --no-log-prefix egress | grep -E 'refused|Established'

# Container writes, host executes — every line "Read-only file system" (".git/config": "Device or resource busy")
$X sh -c 'for p in scripts/x proxy/x .devcontainer/x .git/hooks/x .env .env.secret docker-compose.dev.yml Dockerfile.dev; do touch $p 2>&1; sudo -n touch $p 2>&1; done; git config core.hooksPath /tmp 2>&1'

# No host Docker socket, no capabilities, egress unprivileged and unpublished
DEV=$(docker compose -f docker-compose.dev.yml ps -q dev); EG=$(docker compose -f docker-compose.dev.yml ps -q egress)
docker inspect "$DEV" --format '{{json .Mounts}}' | grep -c docker.sock                       # 0
docker inspect "$DEV" --format 'Privileged={{.HostConfig.Privileged}} CapAdd={{.HostConfig.CapAdd}} User={{.Config.User}}'
docker network inspect "$(docker compose -f docker-compose.dev.yml config --format json | jq -r '.networks.devnet.name')" --format 'devnet internal={{.Internal}}'
docker inspect "$EG" --format 'ports={{json .NetworkSettings.Ports}} user={{.Config.User}}'   # {"3128/tcp":null} tinyproxy
$X sh -c 'ls /var/run/docker.sock; docker ps; grep CapEff /proc/self/status'                # ENOENT, cannot connect, CapEff 0

# Secrets never in the image or the environment listing
docker history --no-trunc "$(docker inspect "$DEV" --format '{{.Config.Image}}')" --format '{{.CreatedBy}}' | grep -icE 'api_key|token=|secret=|password'   # 0
$X sh -c 'env | grep -iE "key|token|secret" | sed "s/=.*/=<value>/"'      # names only

# DoD 3 — an IDE path sees the same /workspace (Dev Containers CLI is the engine VS Code uses)
npx -y @devcontainers/cli@0.89.0 up --workspace-folder .      # prints the containerId of the compose dev service
docker exec <containerId> bash -lc 'id -un; pwd; echo probe > /workspace/.probe'; cat .probe; rm .probe
```

### 5. Record it

Copy the tables below into your project's verification doc
(`.standards/templates/docs/verification.md` has the shape), fill in the
versions `claude --version`, `gemini --version`, `node --version` and
`docker version` printed, and list what you did **not** do — CLI logins and GUI
IDE connections are interactive and belong in that list unless someone sat at
the keyboard.

## Validation record — 2026-10-19 (#158, closes #10)

- **Status:** Historical section (point-in-time record; the procedure above is maintained, this section is not rewritten)
- **Kit version verified:** the `templates/containerized-dev/` shipped by the PR for #158, installed from a worktree at `main` = `b5041e2` plus that PR's changes
- **Related:** #10 (umbrella), #157 (egress sidecar), #159 (`setup.sh --containerized`), [arch-09 §8](../../standards/architecture/arch-09_containerized_agent_dev_standards.md)

### Host

| Component | Observed |
|-----------|----------|
| Host OS | macOS 27.0.1 (Darwin 27.0.0), Apple Silicon (arm64) |
| Docker runtime | Colima `default` profile — aarch64 VM, 4 CPU, 6 GiB, `virtiofs` mounts of `$HOME` |
| Docker Engine | server 29.2.1 (API 1.53), client 29.5.2; `overlayfs`; seccomp `builtin`, apparmor, cgroupns |
| Docker Compose | 5.6.0 |
| Consumer fixture | fresh git repo with the standards as a submodule at `.standards/` (so `.gitmodules` and `.git/modules` exist for the compose mounts), installed with `setup.sh --agents claude-code,cursor --languages typescript --containerized` |

### Versions pinned by this run

| Component | Observed inside the container | Pinned in the kit as |
|-----------|-------------------------------|----------------------|
| Base image, dev | Ubuntu 24.04.5 LTS | `ubuntu:24.04@sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac` (multi-arch manifest) |
| Base image, egress | Alpine 3.21.8 | `alpine:3.21@sha256:ce64758a109eb420d874a118f87920e625e12d3634e03b4a5573fd9f6e5d3507` |
| tinyproxy | 1.11.2-r0 (aarch64), runs as uid 100 `tinyproxy` | floats within the 3.21 branch (Alpine removes superseded builds, so an exact apk pin breaks at the next security rebuild) |
| Node.js | v24.22.0, npm 11.19.1 | `ARG NODE_MAJOR=24` (Node 20 — the previous default — reached end-of-life in April 2026; the first run observed v20.20.2) |
| Claude Code | 2.1.303 | `ARG CLAUDE_CODE_VERSION=2.1.303` |
| Gemini CLI | 0.64.0 | `ARG GEMINI_CLI_VERSION=0.64.0` |
| GitHub CLI | 2.102.0 | apt, floating |
| Docker CLI (client only) | 29.9.1 | apt, floating |
| Python | 3.12.3 | `ARG PYTHON_VERSION=3.12` |
| git | 2.43.0 | apt, floating |
| Image sizes | `consumer-dev` 2.09 GB, `consumer-egress` 13.2 MB | — |

### Definition of Done — observed

| # | arch-09 §8 item | Command (inside `dev` unless noted) | Observed | Verdict |
|---|-----------------|-------------------------------------|----------|---------|
| 1 | `docker compose up` launches a functional environment | `docker compose -f docker-compose.dev.yml up -d --build` | egress built → `Healthy`, then dev `Started`; `ps`: egress `Up (healthy) 3128/tcp`, dev `Up`; rebuild after the kit fixes took 97 s with cached apt layers | PASS |
| 2 | Agent CLIs run a trivial command through the container shell without prompts | `bash -lc 'claude --version && gemini --version && ls'` | `2.1.303 (Claude Code)`, `0.64.0`, workspace listing; `type claude` → `/usr/local/bin/claude` in **both** interactive and non-interactive shells; shim bodies: `exec /usr/bin/claude --dangerously-skip-permissions "$@"`, `exec /usr/bin/gemini --yolo "$@"`; `claude --help` and `gemini --help` list those flags | PASS (prompt-free *flags* proven; logins see "Not verified") |
| 3 | Proxy blocks an unlisted domain — HTTPS | `curl -sS --fail --max-time 10 https://malicious-site.com` | `curl: (22) The requested URL returned error: 403`; egress log `Proxying refused on filtered domain "malicious-site.com"` | PASS |
| 3 | — plain HTTP | `curl -sS --fail --max-time 10 http://malicious-site.com` | exit 22, status `403` | PASS |
| 3 | — suffix spoof of an allowed host | `curl ... https://github.com.evil.example/` | exit 22, refused on `github.com.evil.example` (whole-host match holds) | PASS |
| 3 | — upper-case spelling of an allowed host | `curl ... https://API.GITHUB.COM/` | `CONNECT tunnel failed, response 403` — fnmatch is case-sensitive, fails closed as documented | PASS |
| 3 | — bypassing the proxy variables | `curl --noproxy '*' https://api.github.com`; `env -i PATH=$PATH curl https://api.github.com` | `curl: (6) Could not resolve host` both times — devnet has no route | PASS |
| 3 | — DNS exfiltration | `getent hosts dns-leak-check.example.com`; `getent hosts api.github.com` | exit 2 for both (no external resolution from devnet); `getent hosts egress` → `172.19.0.2` | PASS |
| 3 | Allow path still works | `curl -w '%{http_code}' https://api.github.com`; `sudo -n curl ... https://registry.npmjs.org/`; `sudo -n apt-get update`; `npm view express version`; `pip download six` | `200`; `200` (sudo `env_keep` keeps the proxy); apt fetched 35.8 MB from `ports.ubuntu.com`; `5.3.0`; `Successfully downloaded six`; egress log `Established connection to host "api.github.com"` | PASS |
| 3 | Node's own `fetch()` honours the proxy | `node -e 'fetch("https://api.github.com")...'` | **first run (Node 20): `EAI_AGAIN`** — Node ignores `HTTPS_PROXY` without `NODE_USE_ENV_PROXY=1`; after the fix (Node 24 + the variable in the compose file): `node fetch: 200` | PASS after fix |
| — | Container writes, host executes (threat model) | `touch`/`sudo touch` on `scripts/x proxy/x .devcontainer/x .git/hooks/x .env .env.secret docker-compose.dev.yml Dockerfile.dev Dockerfile.egress .gitmodules`; `git config core.hooksPath /tmp`; `touch .git/modules/.standards/x` | every `touch`: `Read-only file system`; `.git/config`: `could not write config file .git/config: Device or resource busy`; `git status` and `git log` still work for the agent | PASS |
| — | No host Docker socket mounted (§2, P1) | host: `docker inspect <dev> --format '{{json .Mounts}}' \| grep -c docker.sock`; inside: `ls /var/run/docker.sock; docker ps` | `0`; `No such file or directory`; `failed to connect to the docker API at unix:///var/run/docker.sock`; `Privileged=false CapAdd=[] User=developer`; `CapEff: 0000000000000000` | PASS |
| — | Topology | `docker network inspect`; `docker inspect <egress>` | dev on `consumer_devnet` only (`internal=true`); egress on `devnet` + `egressnet` (`internal=false`); egress `ports={"3128/tcp":null}` (unpublished), `user=tinyproxy`, healthcheck `egress-entrypoint.sh healthcheck` → `healthy` | PASS |
| 5 | `.env.secret` git-ignored; no secret in any committed file or image layer | host: `git check-ignore -v .env .env.secret`; `git ls-files \| grep '^\.env'`; `docker history --no-trunc consumer-dev \| grep -icE 'api_key\|token=\|secret=\|password'`; inside: `env \| grep -iE 'key\|token\|secret'` | `.gitignore:16:.env`, `.gitignore:17:.env.secret`; nothing tracked; `0`; empty (no keys were present on this host, so none were captured) | PASS |
| 5 | The `.gitignore` guard | scratch dir without the entry: `ANTHROPIC_API_KEY=… ./scripts/init-workspace.sh` | `Refusing to write .env.secret: .gitignore does not list it.` exit 1, no file; with the entry: `+ captured ANTHROPIC_API_KEY`, file mode `600`, header `# Generated by init-workspace.sh — DO NOT COMMIT.`; a pre-existing hand-made `.env.secret`: `Refusing to write .env.secret: it exists and was not written by this script.` | PASS |
| 4 | An IDE path connects and sees the same `/workspace` | host: `npx -y @devcontainers/cli@0.89.0 up --workspace-folder .` (the Dev Containers CLI, the engine VS Code's "Reopen in Container" drives) then `docker exec <containerId> bash -lc 'id -un; pwd; echo probe > /workspace/.probe'` | `initializeCommand` ran both host scripts; `{"outcome":"success","containerId":"295c4e8b…","composeProjectName":"consumer","remoteUser":"developer","remoteWorkspaceFolder":"/workspace"}`; the id resolves to `/consumer-dev-1`; `developer`, `/workspace`, `/usr/local/bin/claude`; the probe file appeared on the host | PASS (headless; GUI clients see "Not verified") |
| — | Workspace ownership | `echo probe > /workspace/.dod-probe && ls -ln` | `uid 501 gid 20`, i.e. the host user through virtiofs | PASS |

### Kit defects found and fixed in this run

| Finding | Effect before | Fix shipped |
|---------|---------------|-------------|
| YOLO permission was a bash **alias** | `type claude` in a non-interactive shell → `/usr/bin/claude` (no flag): `docker compose exec dev claude -p …`, IDE tasks and scripts would still prompt | `/usr/local/bin/claude` and `/usr/local/bin/gemini` shims that `exec` the real binary with `--dangerously-skip-permissions` / `--yolo`; arch-09 §6 now says shims, not aliases, and names Gemini's real flag |
| Gemini CLI had **no** unattended mode configured | `gemini` prompted for every tool call | the `gemini --yolo` shim (verified against `gemini --help`: `-y, --yolo` / `--approval-mode yolo`) |
| Node ignored the proxy | `node -e 'fetch(...)'` → `EAI_AGAIN` inside devnet | `NODE_USE_ENV_PROXY: "1"` in the compose environment; Node 24 (the first LTS line that honours it) |
| Node 20 default | end-of-life since April 2026 | `ARG NODE_MAJOR=24` |
| Floating bases and CLI versions | two developers get two sandboxes (§3) | `ubuntu:24.04@sha256:…`, `alpine:3.21@sha256:…`, `CLAUDE_CODE_VERSION`, `GEMINI_CLI_VERSION` build args |
| SSH agent on macOS: the host socket path does not exist in the Docker VM | `/ssh-agent` mounted as an empty directory; `ssh-add -l` → `Permission denied` | `init-workspace.sh` writes the VM-side path `/run/host-services/ssh-auth.sock` on Darwin (`CONTAINER_SSH_AUTH_SOCK` overrides) |
| …and compose let the shell's `SSH_AUTH_SOCK` override `.env` | the fix above was silently undone on every macOS shell (which exports `SSH_AUTH_SOCK`): the mount source stayed the launchd path | the mount source has its own key, `SSH_AGENT_SOURCE`; `init-workspace.sh` retires a stale `SSH_AUTH_SOCK` line; verified: mount source `/run/host-services/ssh-auth.sock` with the shell still exporting the launchd path |
| README wording | "Read-only file system" for every protected path | `.git/config` is a single-file mount and answers "Device or resource busy" — documented |

Tests added for the fixes: `scripts/test-containerized-dev.sh` Tests 16c (Dockerfile contract: pins, Node 24, shims, no alias), 18 (`NODE_USE_ENV_PROXY`, `SSH_AGENT_SOURCE` mount), 24 (Darwin/Linux agent-socket branches, override, stale-key retirement). Suite: 36 passed, 0 failed.

### Observations that are not defects

- `id` inside the container shows `gid=20(dialout)`: the macOS host GID (20, `staff`) lands on Ubuntu's existing `dialout` group. Cosmetic — virtiofs maps bind-mount ownership to the host user regardless; documented in `Dockerfile.dev`.
- `useradd` warns `uid 501 outside of the UID_MIN 1000 and UID_MAX 60000 range`; the user is created.
- `gh api` answers `To get started with GitHub CLI, please run: gh auth login` — reached the network through the proxy; no token was present on this host.
- `gemini -p "say hi"` without a key answers with the auth-method error, not a network error — the CLI's own proxy handling works through the sidecar.
- `docker compose build` used the classic builder on this host; the Dockerfiles carry `# syntax=docker/dockerfile:1` and build under BuildKit too.

### Not verified

- **Interactive CLI logins.** No `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` or `GH_TOKEN` was present in the host environment, so `claude` and `gemini` were exercised with `--version`, `--help` and (Gemini) an unauthenticated prompt only. Authenticating is an interactive step (`claude` login flow, `gemini` auth method) or a captured key in `.env.secret`; it is a manual step for whoever runs the environment, not something this record claims.
- **GUI IDE clients.** VS Code "Reopen in Container", Cursor and Zed were not driven. The Dev Containers path was proven through the Dev Containers CLI, which is the same engine VS Code uses; the Zed path needs the opt-in `sshd` + port blocks (left off, as shipped); the Cursor rules file was installed but no Cursor session ran.
- **SSH agent forwarding end to end.** This Colima VM was not started with `--ssh-agent`, so `/run/host-services/ssh-auth.sock` does not exist in the VM and the mount is still an empty directory. The kit now points the mount at the right place; a Docker Desktop host, or Colima with `--ssh-agent`, is needed to see `ssh-add -l` list keys. Not restarted here to avoid changing the developer's VM configuration.
- **Linux host UID/GID mapping** (bind-mount ownership without a VM in between) and **amd64**: this run is arm64 under a VM.
- **`Dockerfile.prod`**: not built — it is an example for a Node service and needs a real app to build.
- **Build-time egress**: by design, `docker compose build` runs on the host network and is unfiltered (arch-09 §4); nothing here checks what the build pulled.

### Residual risk

- The proxy filters by host; an allowed host is allowed for every path. Exfiltration to an allowed host (a public GitHub repo, a package registry) is outside the control. Signal: `docker compose logs egress` lists every `Established connection`; review it.
- Pins drift: Alpine's apk and Ubuntu's apt lines float within their branch by design. Re-run this procedure after bumping any pin and record the result; a bump that is not re-validated reverts the kit to "unverified".
