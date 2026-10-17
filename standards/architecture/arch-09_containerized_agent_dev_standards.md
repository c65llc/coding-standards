# Containerized Agent-Development Environment Standards

These standards govern how a project provides a **sandboxed, reproducible
development container** for autonomous AI coding agents (Claude Code, Gemini CLI,
Cursor, Google Antigravity, and similar). They build on the automation model in
[arch-02_automation_standards.md](./arch-02_automation_standards.md) and the
CI/CD pipeline rules in
[arch-08_ci_cd_pipeline_standards.md](./arch-08_ci_cd_pipeline_standards.md), and
they inherit the P0–P2 severity model from
[../security/sec-01_security_standards.md](../security/sec-01_security_standards.md).

The governing principle: **grant agents broad execution permissions, but only
inside a disposable container that cannot contaminate the host and cannot exfiltrate
data.** "YOLO" autonomy is safe precisely because the blast radius is bounded — a
mounted workspace, a whitelisted network, and a git checkpoint to roll back to. An
agent running with `--dangerously-skip-permissions` **directly on a developer's
host** is a P0 violation; the same agent inside a properly-scoped container is the
intended workflow.

A ready-to-install starter kit implementing these rules lives at
[`templates/containerized-dev/`](../../templates/containerized-dev/). Copy it into a
consumer project and adapt the language toolchain and whitelists.

## 1. Two Images, Two Purposes — Never One

* Ship a **development image** (`Dockerfile.dev`) and a **production image**
  (`Dockerfile.prod`) as separate build targets. They have opposite security
  postures and must never be conflated.
* The **dev image** optimizes for agent capability: a full toolchain, a shell,
  package managers, and the AI CLIs. It is never deployed.
* The **prod image** optimizes for a minimal attack surface via **multi-stage
  builds** — compile in a builder stage, copy only the runtime artifact into a
  distroless or Alpine-minimal final stage. The final image MUST have **no shell,
  no package manager, no AI tooling, and run as a non-root user** `[P0]`. Anything
  an attacker could pivot through that is not required at runtime is a defect.
* CI MUST build and scan the prod image; the dev image is a local convenience and
  SHOULD NOT be published to a public registry.

## 2. Non-Root Developer User with Scoped Sudo

* The dev container runs as a **non-root user** (e.g. `developer`), created at build
  time with a stable, non-zero UID/GID. Running the agent as `root` inside the
  container defeats the point of the sandbox and produces root-owned files on the
  host bind mount.
* Passwordless `sudo` inside the **dev** container is acceptable — it is a
  throwaway sandbox and agents need to install packages mid-task. Passwordless sudo
  in a **prod** image is a P0 violation.
* Match the container UID to the host user's UID where the platform makes host
  ownership matter (Linux bind mounts), so files the agent writes are not
  root-owned on the host. Document the UID assumption next to the Dockerfile.

## 3. The Workspace Is a Volume, the Image Is Disposable

* Mount the codebase into the container at a **canonical absolute path** —
  `/workspace` — via a bind volume. All agent file operations reference this path.
  Nothing the agent needs to keep lives inside the image layer.
* Treat the image as **rebuildable at any time**. A developer must be able to
  `docker compose build --no-cache` and lose nothing but caches. Persist only what
  is intentionally external: the mounted workspace, and named volumes for language
  caches (`~/.cache`, `node_modules` if not bind-mounted, Go module cache) to keep
  rebuilds fast.
* Pin the base OS and every tool version. "Ubuntu 24.04 + Node LTS" is reproducible
  only if LTS resolves to a pinned major and the lockfiles are committed. A floating
  base tag means two developers get two different sandboxes.

## 4. Egress Control — the Dual-Layer Whitelist `[P1]`

An autonomous agent with network access can exfiltrate a repository. Default-deny
egress and allow only what the project needs.

* **Deny by default.** The container's outbound traffic MUST be denied unless the
  destination appears on an allow-list. A dev sandbox that can reach
  `malicious-site.com` has no containment.
* **Two layers, combined at setup time:**
  * a **global** allow-list shipped with the standards
    (`network/global-whitelist.txt`) covering the baseline every project needs —
    package registries, the AI provider APIs, the git host;
  * a **project** allow-list (`proxy/project-whitelist.txt`) for
    project-specific destinations (a private registry, an internal API).
* `setup-proxy.sh` reads both, concatenates and de-duplicates them, and generates
  the runtime enforcement — an egress proxy allow-list, a `NO_PROXY`/`no_proxy`
  set, or firewall rules — that the container runtime applies. The combined list is
  a generated artifact; edit the source lists, never the generated output.
* **Verify the deny path, not just the allow path.** A whitelist that lets every
  listed host through but silently also lets *unlisted* hosts through is worse than
  none — it looks safe. The Definition of Done for any egress change is: a request
  to an unlisted domain is **blocked**, proven by an actual failed request, not by
  reading the config.
* Comment lines (`#`) and blank lines in the whitelist sources are ignored so the
  lists can be self-documenting.

## 5. Identity Injection Without Baking Secrets `[P0]`

Agents need to push commits and call provider APIs, but credentials MUST NOT be
baked into an image layer or committed.

* **SSH agent forwarding, not copied keys.** Forward the host's `SSH_AUTH_SOCK`
  into the container for git operations. Never `COPY` a private key into an image —
  it persists in the layer history even if later deleted.
* **Git identity by mount.** Bind-mount (read-only) or symlink the host
  `~/.gitconfig` so commits carry the right author without duplicating config.
* **API keys via git-ignored env file.** `init-workspace.sh` detects
  `ANTHROPIC_API_KEY` / `GOOGLE_API_KEY` (and peers) in the host environment and
  writes them to a **git-ignored** `.env.secret`, which compose injects at runtime.
  `.env.secret` MUST be in `.gitignore` before it is ever written; a committed key
  is a P0 incident. Prefer values passed at runtime over any value in a build arg —
  build args are visible in image history.
* Keep the setup idempotent: re-running `init-workspace.sh` refreshes identity and
  submodules without clobbering local edits, and skips cleanly when a variable is
  absent rather than writing an empty secret.

## 6. YOLO Permissions Are Earned by the Sandbox, Not Assumed

Zero-friction autonomy is configured **inside the container image only**, and is
paired with a rollback mechanism.

* Pre-configure the agents for unattended execution in the dev image: e.g. a
  `claude` shim that passes `--dangerously-skip-permissions`, and Gemini's
  `terminalPolicy: "auto"` in `.gemini/settings.json`. These settings MUST live in
  the container, never in a developer's host dotfiles.
* **Checkpoint before autonomy.** Agents MUST be instructed (via the assembled
  agent config) to create a git checkpoint — a commit or a `git stash` /
  `wip/` branch — before running a batch of unattended, destructive-capable
  commands, so any run is instantly recoverable. See
  [../process/proc-02_git_version_control_standards.md](../process/proc-02_git_version_control_standards.md).
* The combination is the control: broad permissions + bounded blast radius +
  one-command rollback. Remove any one leg and the "YOLO" posture becomes reckless.

## 7. IDE Integration Is Scripted and Optional

Every editor connects to the **same container and the same `/workspace`** so the
CLI agents and the human see one filesystem. Provide bootstrap scripts rather than
manual setup docs, and make each opt-in.

* **VS Code Dev Containers:** ship `.devcontainer/devcontainer.json` pointing at
  `docker-compose.dev.yml` so "Reopen in Container" just works, with the project's
  agent extensions declared.
* **Cursor:** a root `.cursorrules` instructing the agent to execute terminal
  commands inside the container and treat `/workspace` as the absolute root.
* **Zed (headless remote):** a bootstrap script that adds an SSH `Host` entry for
  the container's forwarded port and installs the Zed remote server inside it.
* **Google Antigravity:** a bootstrap script that registers the container shell in
  the Agent Manager and pre-loads project MCP configs.
* Keep IDE bootstrap scripts **non-destructive** — append an SSH `Host` block or
  MCP entry, detect and skip if already present, and never rewrite a user's
  `~/.ssh/config` or global editor settings wholesale.

## 8. Definition of Done for a Container Change

A change to the dev-container setup is done only when:

* `docker compose up` launches a functional dev environment and the agent CLIs run
  a trivial command (`ls`) through the container shell **without permission
  prompts**.
* The egress proxy **blocks** a request to an unlisted domain — demonstrated by a
  failing request, per §4.
* At least one IDE path (Dev Containers or Cursor) connects and sees the same
  `/workspace` the CLI agents see.
* No secret, private key, or API key appears in any committed file or image layer,
  and `.env.secret` is git-ignored.
