# Containerized Agent-Development Starter Kit

A ready-to-adapt implementation of
[arch-09_containerized_agent_dev_standards.md](../../standards/architecture/arch-09_containerized_agent_dev_standards.md):
a sandboxed, reproducible Docker environment that gives AI coding agents (Claude
Code, Gemini CLI, Cursor, Antigravity) broad execution permissions **inside a
container that can't contaminate the host or exfiltrate data**.

> These are **templates**, not a turnkey product. Copy them into a consumer
> project, pin tool versions, adapt the language toolchain, and populate the
> whitelists. Then validate against the Definition of Done in arch-09 §8.

## Contents

| File | Purpose | arch-09 |
|------|---------|---------|
| `Dockerfile.dev.example` | Full-toolchain dev image, non-root sudo user, baked YOLO agent config | §1, §2, §6 |
| `Dockerfile.prod.example` | Multi-stage → distroless, no shell, non-root | §1 |
| `docker-compose.dev.yml.example` | Wires workspace volume, identity, secrets, egress vars | §3, §4, §5 |
| `scripts/init-workspace.sh.example` | Entry point: identity forwarding, secret capture, submodule sync | §5 |
| `scripts/setup-proxy.sh.example` | Combines the dual-layer whitelist into egress rules | §4 |
| `scripts/bootstrap-zed.sh.example` | Headless Zed remote over SSH | §7 |
| `scripts/bootstrap-antigravity.sh.example` | Register container with Antigravity Agent Manager | §7 |
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
./scripts/setup-proxy.sh                                 # generate egress allow-list
docker compose -f docker-compose.dev.yml up -d --build
docker compose -f docker-compose.dev.yml exec dev bash   # drop into the sandbox
```

## Validate (Definition of Done — arch-09 §8)

```bash
# 1. Agents run without permission prompts
docker compose -f docker-compose.dev.yml exec dev bash -lc 'claude --version && gemini --version && ls'

# 2. Egress deny path works — this MUST fail
docker compose -f docker-compose.dev.yml exec dev curl -sS --max-time 5 https://malicious-site.com && \
  echo "FAIL: unlisted host was reachable" || echo "OK: unlisted host blocked"

# 3. An allowed host works
docker compose -f docker-compose.dev.yml exec dev curl -sS --max-time 5 -o /dev/null -w '%{http_code}\n' https://api.github.com
```
