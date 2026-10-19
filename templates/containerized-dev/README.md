# Containerized Agent-Development Starter Kit

A ready-to-adapt implementation of
[arch-09_containerized_agent_dev_standards.md](../../standards/architecture/arch-09_containerized_agent_dev_standards.md):
a reproducible Docker environment that gives AI coding agents (Claude Code,
Gemini CLI, Cursor, Antigravity) broad execution permissions inside a container,
with the scaffolding needed to bound that container's blast radius.

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
| No secrets baked into layers; `.env.secret` must be git-ignored (§5) | Enforced — `init-workspace.sh` refuses to write an un-ignored secret file |
| YOLO permissions live only in the image (§6) | Enforced by `Dockerfile.dev` |
| Host Docker socket | **Not mounted.** Opt-in, commented out in the compose file with the trade-off spelled out; enabling it hands the container root-equivalent control of the host |
| **Deny-by-default egress (§4)** | **Not enforced.** `setup-proxy.sh` generates the allow-list artifact and the compose file sets the `*_PROXY` variables, but nothing blocks direct outbound traffic until you add an enforcing proxy sidecar on an `internal: true` network (or host firewall rules). Tracked in [#157](https://github.com/c65llc/coding-standards/issues/157). Until then the deny-path check below will **pass traffic**, and the environment must not be described as contained |
| Zed over SSH (§7) | Opt-in: `bootstrap-zed.sh` preflights for sshd and a published port and refuses to configure anything until both opt-in blocks are enabled |

## Contents

| File | Purpose | arch-09 |
|------|---------|---------|
| `Dockerfile.dev.example` | Full-toolchain dev image, non-root sudo user, baked YOLO agent config | §1, §2, §6 |
| `Dockerfile.prod.example` | Multi-stage → distroless, no shell, non-root | §1 |
| `docker-compose.dev.yml.example` | Wires workspace volume, identity, secrets, proxy pointer (both env-var cases); Docker socket and SSH port are commented opt-ins | §3, §4, §5 |
| `scripts/init-workspace.sh.example` | Entry point: identity forwarding, secret capture, submodule sync; rewrites only its own keys in `.env` | §5 |
| `scripts/setup-proxy.sh.example` | Combines the dual-layer whitelist into `proxy/allowlist.generated.txt` for an enforcing proxy to consume; does not block traffic itself | §4 |
| `scripts/bootstrap-zed.sh.example` | Headless Zed remote over SSH (requires the sshd + port opt-ins; preflights both) | §7 |
| `scripts/bootstrap-antigravity.sh.example` | Register container with Antigravity Agent Manager; merges, never overwrites, an existing MCP config | §7 |
| `network/global-whitelist.txt` | Baseline egress allow-list (ships with standards) | §4 |
| `proxy/project-whitelist.txt` | Project-specific egress allow-list | §4 |
| `.devcontainer/devcontainer.json` | VS Code Dev Containers integration | §7 |
| `cursorrules.example` | Cursor "run in container" rules | §7 |
| `env.secret.example` | Shape of the git-ignored runtime secret file | §5 |

## Install

```bash
# From the consumer project root, with these standards vendored at coding_standards/
cp coding_standards/templates/containerized-dev/Dockerfile.dev.example        Dockerfile.dev
cp coding_standards/templates/containerized-dev/Dockerfile.prod.example       Dockerfile.prod
cp coding_standards/templates/containerized-dev/docker-compose.dev.yml.example docker-compose.dev.yml
mkdir -p scripts proxy .devcontainer
cp coding_standards/templates/containerized-dev/scripts/*.example             scripts/
for f in scripts/*.example; do mv "$f" "${f%.example}"; chmod +x "${f%.example}"; done
cp coding_standards/templates/containerized-dev/proxy/project-whitelist.txt   proxy/
cp coding_standards/templates/containerized-dev/.devcontainer/devcontainer.json .devcontainer/

# Never commit secrets — ignore the generated files first (P0, arch-09 §5).
printf '\n.env\n.env.secret\n' >> .gitignore
```

## Run

```bash
./scripts/init-workspace.sh                              # identity + secrets + submodules
./scripts/setup-proxy.sh                                 # generate proxy/allowlist.generated.txt
docker compose -f docker-compose.dev.yml up -d --build
docker compose -f docker-compose.dev.yml exec dev bash   # drop into the container
```

Re-running either script is safe: `init-workspace.sh` and `setup-proxy.sh` each
rewrite only the `.env` keys they own and leave every other line alone.

## Validate (Definition of Done — arch-09 §8)

```bash
# 1. Agents run without permission prompts
docker compose -f docker-compose.dev.yml exec dev bash -lc 'claude --version && gemini --version && ls'

# 2. Egress deny path works — this MUST fail. With the template as shipped (no
#    enforcing proxy, bridge network) it will SUCCEED, which means egress is not
#    contained and the DoD is not met. Add the enforcing layer (#157) first.
docker compose -f docker-compose.dev.yml exec dev curl -sS --max-time 5 https://malicious-site.com && \
  echo "FAIL: unlisted host was reachable" || echo "OK: unlisted host blocked"

# 3. An allowed host works
docker compose -f docker-compose.dev.yml exec dev curl -sS --max-time 5 -o /dev/null -w '%{http_code}\n' https://api.github.com
```
