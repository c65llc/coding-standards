# Security Standards

> **Severity Model:** Rules are tagged P0 (Critical), P1 (High), or P2 (Medium).
> P0 and P1 findings **must block merge**. P2 findings should be flagged as warnings.
>
> This framework is inspired by [Omar Gate](https://github.com/marketplace/actions/omar-gate)'s multi-layer security analysis model.

## 1. Injection Prevention

### SQL Injection `[P0]`

- **Use parameterized queries exclusively.** Never construct SQL via string concatenation or interpolation with user input.
- ORMs and query builders are preferred. Raw SQL must use bind parameters.

```python
# BAD — P0 violation
query = f"SELECT * FROM users WHERE id = {user_input}"
cursor.execute(query)

# GOOD
cursor.execute("SELECT * FROM users WHERE id = %s", (user_input,))
```

```ruby
# BAD — P0 violation
User.where("name = '#{params[:name]}'")

# GOOD
User.where(name: params[:name])
```

```typescript
// BAD — P0 violation
const query = `SELECT * FROM users WHERE id = ${userId}`;

// GOOD
const result = await db.query("SELECT * FROM users WHERE id = $1", [userId]);
```

### Command Injection `[P0]`

- **Never pass unsanitized user input to shell commands, `eval()`, `exec()`, or `system()`.**
- Use language-specific safe APIs instead of shell invocation.
- If shell execution is unavoidable, use allowlists for permitted commands and arguments.

```python
# BAD — P0 violation
os.system(f"convert {user_filename} output.png")
subprocess.call(user_input, shell=True)

# GOOD
subprocess.run(["convert", validated_filename, "output.png"], shell=False)
```

```javascript
// BAD — P0 violation
eval(userInput);
require("child_process").exec(userCommand);

// GOOD
require("child_process").execFile("convert", [validatedFilename, "output.png"]);
```

### Cross-Site Scripting (XSS) `[P1]`

- **Encode all output rendered in HTML contexts.** Use framework-provided escaping by default.
- Never use `innerHTML`, `dangerouslySetInnerHTML`, or `v-html` with untrusted data.
- Configure Content Security Policy (CSP) headers to restrict inline scripts.

```javascript
// BAD — P1 violation
element.innerHTML = userInput;

// GOOD
element.textContent = userInput;
```

```jsx
// BAD — P1 violation
<div dangerouslySetInnerHTML={{ __html: userInput }} />

// GOOD
<div>{userInput}</div>
```

### Server-Side Request Forgery (SSRF) `[P1]`

- **Validate and sanitize all URL inputs.** Allowlist permitted domains and protocols.
- Block requests to internal/private IP ranges (`10.x`, `172.16-31.x`, `192.168.x`, `127.x`, `169.254.x`).
- Do not allow user input to control the full URL of outbound HTTP requests.

### Template Injection `[P1]`

- **Never pass user input directly into template expressions or template strings that are evaluated server-side.**
- Use sandboxed template engines. Separate data from template logic.

## 2. Authentication & Authorization

### Authentication Bypass `[P0]`

- **Never implement custom authentication logic when framework/library solutions exist.**
- Verify authentication on every request — do not rely on client-side checks alone.
- Token validation must check expiration, signature, and issuer.
- Never compare secrets or tokens with `==` — use constant-time comparison functions.

```python
# BAD — P0 violation (timing attack)
if provided_token == stored_token:
    grant_access()

# GOOD
import hmac
if hmac.compare_digest(provided_token, stored_token):
    grant_access()
```

### Authorization Checks `[P1]`

- **Every endpoint must enforce authorization.** Verify the authenticated user has permission for the specific resource and action.
- Never rely solely on hiding UI elements for access control.
- Use RBAC or policy-based authorization. Check permissions server-side on every request.

### CSRF Protection `[P1]`

- **Enable CSRF protection on all state-changing endpoints** (POST, PUT, PATCH, DELETE).
- Use framework-provided CSRF mechanisms (Rails `protect_from_forgery`, Django CSRF middleware, etc.).
- API endpoints using token-based auth (Bearer tokens) are exempt but must validate the token on every request.

### Session Management `[P1]`

- Set secure cookie attributes: `Secure`, `HttpOnly`, `SameSite=Strict` (or `Lax`).
- Regenerate session IDs after authentication.
- Implement session expiration and idle timeouts.

## 3. Secrets Management

### Hardcoded Credentials `[P0]`

- **Never commit secrets, API keys, passwords, tokens, or credentials to source code.**
- Use environment variables, secret management services (AWS Secrets Manager, HashiCorp Vault, GCP Secret Manager), or framework credential systems (Rails credentials).
- Scan for secrets in CI with tools like `git-secrets`, `truffleHog`, or `detect-secrets`.

Common patterns to detect and reject:

```text
# BAD — P0 violations (any of these patterns in source code)
API_KEY = "sk-abc123..."
password = "hardcoded_password"
aws_secret_access_key = "AKIA..."
DATABASE_URL = "postgres://user:pass@host/db"
private_key = "-----BEGIN RSA PRIVATE KEY-----"
```

### Scanner False Positives on Test Fixtures `[P1]`

Test fixtures trip secret scanners for predictable reasons: UUIDv7 ids look
like tokens, a redaction test needs a plausible password to redact, a fake
credential in a `*_test` file is the point of the test. Two consumer repos each
needed two allowlist rounds for the same fixtures before the scanner went
quiet, and the second round in each case excluded a whole directory. Noisy
scanners get disabled; the P0 rule above only holds while the allowlist keeps
signal high.

- **Suppress at the finest granularity that works, in this order.** (1) An
  inline marker on the exact line, written in the file's own comment syntax
  — `trufflehog:ignore` for TruffleHog, `gitleaks:allow` for Gitleaks, both
  when both scanners run: `// gitleaks:allow` in JavaScript, Go or Rust,
  `# gitleaks:allow` in Python, Ruby, shell, YAML or TOML. The scanners look
  for the token, not the comment leader; a `//` pasted into a Python fixture
  breaks the fixture. (2) A
  **shape-based** allowlist regex, global only when the shape cannot work as
  a credential anywhere (`REDACTED`/`****` redaction output). A shape a real
  secret *can* take — a UUID (many services issue UUID API keys), a
  `test-`/`changeme`-style value or a repeated-character pad (in production
  config those are weak *default* credentials, §6 P0) — is never allowlisted
  globally; it is confined to fixture locations with a path-AND-shape
  condition (Gitleaks ≥ 8.25 `[[allowlists]] condition = "AND"`) or marked
  inline. (3) A path exclude, only for a named artifact that provably cannot
  carry a credential. Neither a committed build output (`dist/`, `*.min.js`:
  where a build-time-injected credential lands) nor a lockfile (registry URLs
  the package manager wrote, token and all) qualifies, so the template ships
  no path excludes.
- **Never exclude `tests/`, `fixtures/` or `__tests__/` wholesale.** A real
  secret pasted into a test file must still be caught; the shape allowlist
  covers the fixture forms without opening that hole.
- **Name fixtures so the scanner can tell.** Fake credentials carry a `test-`,
  `fake-`, `dummy-`, `example-` or `not-a-real-` prefix (or are the literal
  `changeme`); id fixtures are well-formed UUIDs that live in test paths. The
  convention is what the shape regexes key on, so a fixture that follows it
  never needs a second allowlist round.
- **Every allowlist entry states why it exists** — a comment naming the fixture
  family it covers. A bare regex nobody can explain is removed at the next
  review.

Ship-with-standards template: [`templates/.gitleaks.toml.example`](../../templates/.gitleaks.toml.example)
(Gitleaks ≥ 8.25: one global shape for redaction output; a path-AND-shape
block for naming-convention fakes, repeated-character padding and UUID
fixtures; no stopwords — a substring match would drop a real
`prod-example-…` secret — and no path excludes, with a commented per-artifact
example).
TruffleHog
takes only path excludes (`.trufflehog-ignore`), so its per-finding
suppression is the inline `trufflehog:ignore` marker. The scanner workflow
itself is in §9.

### .env File Handling `[P1]`

- **Never commit `.env` files to version control.** Add `.env` to `.gitignore`.
- Provide `.env.example` with placeholder values (never real credentials).
- In production, use secret management services — not `.env` files.

### Credential Rotation `[P2]`

- Rotate credentials on a regular schedule.
- Implement credential rotation without downtime.
- Log credential access for audit purposes.

## 4. Dangerous Functions & Patterns

### Banned Functions `[P0]`

Never use these functions with untrusted input. If used with trusted input, add a comment explaining why.

| Language | Banned Functions |
|----------|-----------------|
| Python | `eval()`, `exec()`, `pickle.loads()` (untrusted), `yaml.load()` (use `safe_load`), `os.system()`, `subprocess.call(..., shell=True)` |
| JavaScript/TypeScript | `eval()`, `Function()`, `setTimeout(string)`, `setInterval(string)`, `document.write()` |
| Ruby | `eval()`, `send()` with user input, `system()` with interpolation, `Marshal.load()` (untrusted), `YAML.load()` (use `YAML.safe_load`) |
| Java/Kotlin | `Runtime.exec()` with string, `ObjectInputStream.readObject()` (untrusted), `ScriptEngine.eval()` |
| Rust | `std::process::Command` with unsanitized input |
| Swift | `NSExpression` with user input, `Process` with unsanitized args |
| C/C++ | `gets()`, `strcpy()`, `strcat()`, `sprintf()`, `vsprintf()`, `scanf("%s")` without a width, `strtok()`, `system()`, `popen()`, `tmpnam()`, `alloca()`, `atoi()`/`atol()`/`atof()` on untrusted input (use `std::from_chars`) — see [lang-14 §17](../languages/lang-14_cpp_standards.md) |

### Insecure Deserialization `[P0]`

- **Never deserialize untrusted data using native serialization formats** (Python pickle, Java ObjectInputStream, Ruby Marshal, PHP unserialize).
- Use safe data formats (JSON, Protocol Buffers) for untrusted data exchange.
- If native deserialization is required, validate and sanitize before deserializing.

### Insecure Randomness `[P1]`

- **Use cryptographically secure random number generators for security contexts** (tokens, keys, session IDs, nonces).

| Language | Insecure (avoid for security) | Secure (use for security) |
|----------|-------------------------------|---------------------------|
| Python | `random.random()` | `secrets.token_urlsafe()`, `secrets.token_hex()` |
| JavaScript | `Math.random()` | `crypto.randomUUID()`, `crypto.getRandomValues()` |
| Ruby | `rand()` | `SecureRandom.hex()`, `SecureRandom.uuid()` |
| Java/Kotlin | `java.util.Random` | `java.security.SecureRandom` |
| Rust | — | `rand::rngs::OsRng` (already secure by default) |
| C/C++ | `rand()`, `std::mt19937` and other `<random>` engines | OS CSPRNG: `getrandom(2)`, `SecRandomCopyBytes`, `BCryptGenRandom`, or libsodium/OpenSSL 3 |

## 5. Dependency & Supply Chain Security

### Known CVE Scanning `[P1]`

- **Run dependency vulnerability scanning in CI/CD.** Block merges on critical/high CVEs.

| Language | Tool |
|----------|------|
| Python | `pip-audit`, `safety` |
| JavaScript/TypeScript | `pnpm audit`, `npm audit`, `yarn audit` |
| Ruby | `bundler-audit` (`bundle-audit` command) |
| Java/Kotlin | OWASP Dependency-Check, `gradle dependencyCheckAnalyze` |
| Rust | `cargo audit`, `cargo deny` |
| Swift | — (use GitHub Dependabot) |
| Dart | — (use GitHub Dependabot) |
| Zig | — (manual review) |

### Lock File Requirements `[P1]`

- **Always commit lock files** (`package-lock.json`, `Gemfile.lock`, `Cargo.lock`, `poetry.lock`, etc.).
- CI must install from lock files (`npm ci`, `BUNDLE_FROZEN=1 bundle install`, etc.).

### HTTP Dependency Prohibition `[P2]`

- **Never use HTTP (non-HTTPS) URLs for package registries or dependency sources.**
- All dependency sources must use HTTPS.

### Dependency Pinning `[P2]`

- Pin major and minor versions in production dependencies.
- Review and test dependency updates before merging.
- A patch applied to a dependency (`patch-package`, pnpm `patchedDependencies`,
  Cargo `[patch]`, a fork pin) is a fork you now maintain: a patch file lives
  under `patches/`, and every override — file-backed or manifest-only (a
  `[patch]` table, a git `rev` pin) — is recorded in `patches/README.md` with
  its reason, regression test and removal criterion (core-standards, "Package
  Patches").

### Automated Dependency Updates `[P2]`

- **Grouped updates are required** for every ecosystem a bot (Dependabot,
  Renovate) watches. One PR per package produces a queue nobody reviews: a
  consumer hand-merged 10–13 bot PRs at a time in thirteen "omnibus" commits
  because `cargo` had `groups` and `npm` did not. Batch minor + patch bumps per
  ecosystem per week; keep majors as their own PRs (except GitHub Actions, where
  majors are frequent and low-risk).
- **Group partners that only break in company.** Packages that must move in
  lockstep (`react` + `react-dom`, `@typescript-eslint/*`, `vite` + `@vitejs/*`,
  `tokio` + `tokio-*`) break when one is bumped alone. A pattern group puts
  their available updates in one PR; it does not make Dependabot wait for the
  partner, so the invariant itself is a CI assertion on the lockfile (arch-07
  §3 lockstep pins) and the group is what keeps that assertion green. List
  the project's lockstep sets explicitly in the config — the defaults do not
  know them.
- Bot PRs are ordinary PRs: Conventional Commit prefix (`chore(deps)`), the full
  CI gate, and the age gate below. A grouped PR that pulls in a version younger
  than 72 hours waits like any other.
- A patched package is re-patched when its group lands; `patches/README.md`
  says how, and the regression test it names is what proves the patch survived.

Template: [`templates/dependabot.yml.example`](../../templates/dependabot.yml.example)
(npm, cargo and github-actions groups, with lockstep pattern groups and a
separate security-update group).

### Dependency Age Gate `[P1]`

- **Never adopt a 3rd-party dependency version published less than 72 hours (3 days) ago.** This mitigates supply-chain attacks where malicious code is injected into a new release and detected/reverted within the first few days.
- Applies to **all languages and package ecosystems** — PyPI, npm, crates.io, RubyGems, Maven Central, pub.dev, Swift packages, and Zig packages.
- **CI enforcement:** Validate the publish date of every added or upgraded dependency against its registry. Block merges when any dependency version is younger than 3 days.
- **Exception process:** Emergency security patches (e.g., a critical CVE fix) may bypass the age gate with:
  1. Explicit approval from a team lead or security owner.
  2. A documented justification in the PR description.
  3. A follow-up review within 24 hours of the bypass.

**Reference implementation: override label + 24 h follow-up.** The three
conditions above are enforceable; make the bypass a visible, audited path
rather than a disabled check. Consumers that lacked one ended up with
"dep-age overridden" commits, a pin justified by "the audit lane is red on
main", and no record of who agreed or when the pin was re-examined. The age
checker itself (`dep-age-check.sh` in the excerpt) is the consumer's: its
whole contract is "exit non-zero when a version this PR adds or upgrades is
younger than the threshold", and the registry table at the end of this
section names the publish-date field per ecosystem. The excerpt is the
override path around it.

1. **Label, approval comment and body block, all required.** The age-gate
   job honors a failure only when the PR carries the `dep-age-override`
   label, a listed approver has posted the approval comment described next,
   **and** the PR body contains a `Dep-age override: <package>@<version> —
   <advisory>` line for **every** version the checker rejected (a grouped
   bump with three young versions needs three lines; a line naming some
   other package covers nothing), plus an `Approved-by: @security-owner`
   line naming that approver. Any part missing keeps the gate red. Nobody
   sets `continue-on-error`, deletes the job, or merges on red.
2. **The approval is a comment bound to the head commit.** Anyone with
   triage access can apply a label and anyone can edit a PR body, so neither
   proves who approved what. The approver posts a PR comment
   `Dep-age approved: <full head SHA>`; the gate accepts it only when the
   comment's author is listed in the `DEP_AGE_APPROVERS` repository variable
   (the security owner and team leads), is not the PR author, and the SHA is
   the head the gate is running on. A comment cannot be authored by someone
   else, and the SHA cannot be backdated or edited into existence by the
   author, so a push after approval needs a fresh comment for the new head.
   The label remains the visible signal the merge-time job keys on, and it is
   also the trigger: comments are not `pull_request` events, so the approver
   posts the comment first and then applies the label (re-applies it after a
   push), and removing the label is how an approval is revoked — the run
   re-evaluates and goes red regardless of what comments exist.
3. **Merging opens the follow-up.** A second, trusted workflow runs when the
   PR is merged (`pull_request_target` on `closed`, base-repository context,
   nothing from the PR checked out or executed) and creates an issue
   `dep-age follow-up: <package>@<version>`, labelled `dep-age-follow-up`,
   assigned to the approver, with two checkpoints computed from `merged_at`
   and a stable marker `dep-age-follow-up-for-pr-<n>` so a rerun finds the
   existing issue instead of opening a duplicate. `Due:` (24 h) is the review:
   the approver — the author of the approval comment for the merged head,
   frozen at merge in the workflow's own comment on the PR — comments that
   the advisory still stands and the version shows no yank or new advisory so
   far. `Matures:` (72 h) is the close condition:
   the version has aged past the gate with no yank or advisory, or it was
   rolled back. Two dates because a one-hour-old emergency pin cannot be
   confirmed mature at the 24 h mark. The split is deliberate: the gate's
   `pull_request` run holds a read-only token on Dependabot and fork PRs (no
   `permissions:` grant changes that for forks), and the 24 h clock must not
   start while the PR is still open. The job declares `issues: write` and
   re-asserts the `dep-age-follow-up` label with `gh label create --force`
   before `gh issue create`, which only applies an existing label. It keys on
   the label alone, which is sound only because the gate refuses a label the
   age check no longer needs: a PR cannot be green with `dep-age-override`
   present and the age check passing, so at merge the label means an override
   was honored.
4. **A red advisory lane is not an override.** Moving the CVE audit from the
   required gate to a nightly job (arch-08 §2) is the right response to a
   transitive advisory that would otherwise wedge every merge; it does not
   waive the age gate for the pin that fixes it. The pin waits 72 h or goes
   through the label.
5. **The record is the label, the body block and the issue.** A nightly
   audit (third excerpt below) finds follow-ups by their marker in every
   state and fails on one that passed `Due:` with no `Reviewed:` comment from
   the approver posted before it, one still open a day past `Matures:`, one
   closed at or after `Matures:` by anyone other than the approver, or one
   closed before `Matures:` without a `Rolled back:` comment from the
   approver posted by the close. Deadlines are recomputed from the PR's
   `mergedAt`, and the approver is read from the record the merge-time job
   froze in its own comment on the PR, so editing the issue body or
   reassigning it changes nothing. Roster membership is judged at the merge,
   not nightly, so a lead who later rotates off `DEP_AGE_APPROVERS` does not
   turn every follow-up they approved red. A forgotten, late or prematurely
   closed follow-up surfaces on its own and stays red until it is reopened or
   the approver records the rollback.

```yaml
# .github/workflows/dep-age-gate.yml (excerpt) — the gate, on the PR.
# Read-only on purpose: a Dependabot or fork pull_request run never gets a
# write token, and this job does not need one.
on:
  pull_request:
    # The default types (opened, synchronize, reopened) would leave a green
    # check attached to the commit after the label or the body block changed.
    # Label and body edits re-run the gate so removing either turns it red.
    # Comments are not pull_request events, so the LABEL is the trigger: the
    # approver posts `Dep-age approved: <sha>` first, then applies the label
    # (re-applies it after a push); removing the label revokes — the run goes
    # red whatever comments exist.
    types: [opened, synchronize, reopened, labeled, unlabeled, edited]
# ci-hygiene: paths-exempt this is a REQUIRED check, so it must create a check
# run on every PR — a `paths:` filter would leave non-manifest PRs waiting on a
# status that never arrives (arch-08 §3.1: paths-filter + always-run gate, or
# exempt). The checker itself returns in seconds when the lockfile diff is
# empty, so running on every PR costs nothing.
#
# One run per PR; a label or body edit cancels the run it supersedes instead of
# stacking registry lookups (arch-08 §3.1).
concurrency:
  group: dep-age-${{ github.event.pull_request.number }}
  cancel-in-progress: true
jobs:
  dep-age:
    runs-on: ubuntu-latest
    timeout-minutes: 10   # registry lookups hang on a bad network; never the 6 h default
    permissions:
      contents: read
      pull-requests: read
    steps:
      - uses: actions/checkout@<pinned-sha> # vN
        with:
          # The checker diffs lockfiles against the PR base; the default
          # single-commit checkout has no base to diff against.
          fetch-depth: 0
      - name: Dependency age gate (72 h)
        id: age
        # CONSUMER-SUPPLIED. Contract: exit 0 when every dependency version
        # added or upgraded by this PR (lockfile diff against the base) was
        # published >= 72 h ago; otherwise exit 1 and write the offenders, one
        # `<package>@<version>` per line, to the `--offenders` path, and ONLY
        # after every lookup succeeded write `<path>.done` (the completion
        # marker). A registry error is exit 2 with no marker: an incomplete
        # scan is not a rejection and must not enter the override path. The
        # registry field per ecosystem is in the table below this excerpt; a
        # short script per ecosystem that reads the lockfile diff and that
        # field is enough. The override step reads only those two files.
        # Run the BASE branch's copy: the PR may edit the checker, and a gate
        # must never execute code supplied by the change it gates.
        env:
          BASE_REF: ${{ github.event.pull_request.base.ref }}
        run: |
          # The report lives OUTSIDE the checkout ($RUNNER_TEMP) and any file of
          # that name inside the checkout is removed first, so a PR cannot
          # commit an offenders list of its own choosing for the override step
          # to read when the checker fails before writing one.
          rm -f age-offenders.txt age-offenders.txt.done "$RUNNER_TEMP/age-offenders.txt" "$RUNNER_TEMP/age-offenders.txt.done"
          git show "origin/$BASE_REF:scripts/dep-age-check.sh" > "$RUNNER_TEMP/dep-age-check.sh" \
            || { echo "no dep-age-check.sh on the base branch"; exit 1; }
          chmod +x "$RUNNER_TEMP/dep-age-check.sh"
          "$RUNNER_TEMP/dep-age-check.sh" --max-age-hours 72 --offenders "$RUNNER_TEMP/age-offenders.txt"
        continue-on-error: true
      - name: Refuse a stale dep-age-override label
        # The merge-time job opens the follow-up whenever the label is present,
        # so a label left on a PR whose age check now passes (the version aged
        # past 72 h, or the upgrade was dropped) would record a bypass that
        # never happened. Red until the label is removed; `unlabeled` re-runs.
        if: steps.age.outcome == 'success' && contains(github.event.pull_request.labels.*.name, 'dep-age-override')
        run: |
          echo "the age gate passes; remove the dep-age-override label — no override is needed and none will be recorded"
          exit 1
      - name: Honor dep-age-override (label + head-bound approval comment + body block, all required)
        if: steps.age.outcome == 'failure'
        env:
          # The label array as JSON — never a joined string, since a label
          # name may itself contain the delimiter (`dep-age-override,anything`).
          LABELS_JSON: ${{ toJSON(github.event.pull_request.labels.*.name) }}
          BODY: ${{ github.event.pull_request.body }}
          AUTHOR: ${{ github.event.pull_request.user.login }}
          HEAD_SHA: ${{ github.event.pull_request.head.sha }}
          PR: ${{ github.event.pull_request.number }}
          REPO: ${{ github.repository }}
          APPROVERS: ${{ vars.DEP_AGE_APPROVERS }}  # repository variable: comma-separated handles
          GH_TOKEN: ${{ github.token }}
        run: |
          APPROVERS=$(printf '%s' "$APPROVERS" | tr -d '[:space:]')   # `alice, bob` → `alice,bob`
          # The label must be on the PR now (the follow-up job keys on it too),
          # tested as an exact array element …
          printf '%s' "$LABELS_JSON" | jq -e 'index("dep-age-override") != null' >/dev/null \
            || { echo "age gate failed; no dep-age-override label"; exit 1; }
          # … and the approval is a PR comment `Dep-age approved: <head sha>`
          # by a listed approver who is not the author. A comment cannot be
          # authored by someone else and the SHA binds it to this exact head:
          # a push after approval needs a fresh comment, and no timestamp —
          # which a commit's author controls — is involved.
          actor=$(gh api "repos/$REPO/issues/$PR/comments" --paginate --slurp \
            | jq -r --arg sha "$HEAD_SHA" --arg list ",$APPROVERS," --arg author "$AUTHOR" \
                '[.[][] | select((.body | test("^Dep-age approved: " + $sha + "([[:space:]]|$)"))
                                 and (.user.login as $u | ($list | index("," + $u + ",")) != null)
                                 and .user.login != $author)] | last | .user.login // empty') \
            || { echo "could not read PR comments"; exit 1; }
          [ -n "$actor" ] || { echo "no 'Dep-age approved: $HEAD_SHA' comment by a listed approver other than the author — approval is bound to the head; a push needs a fresh one"; exit 1; }
          # The body must cover EVERY offender the checker named — one
          # `Dep-age override: <package>@<version> <advisory text>` line each,
          # matched literally (so `@scope/pkg@1.2.3` works) and followed by a
          # justification. A grouped bump with three young versions needs
          # three lines; a body naming some other package proves nothing.
          # The report the TRUSTED checker wrote, outside the checkout, AND its
          # completion marker: a report without `.done` means the scan stopped
          # early (a registry lookup failed after some offenders were written),
          # so an approval covering the partial list would bypass versions that
          # were never checked. At least one well-formed line is also required.
          offenders="$RUNNER_TEMP/age-offenders.txt"
          [ -f "$offenders.done" ] \
            || { echo "the age checker did not complete its scan (no completion marker); an incomplete scan is not a rejection — fix the checker run, do not override"; exit 1; }
          grep -Eq '^[^[:space:]]+@[^[:space:]]+$' "$offenders" 2>/dev/null \
            || { echo "the age checker failed without naming offenders; cannot honor an override"; exit 1; }
          rc=0
          while IFS= read -r offender; do
            [ -n "$offender" ] || continue
            lit=$(printf '%s' "$offender" | sed 's/[][\.*^$+?(){}|\\/]/\\&/g')
            # After the offender: whitespace, an optional dash/colon separator, then advisory text
            # that is itself not a separator — `foo@1.2.3 —` alone does not pass.
            printf '%s\n' "$BODY" | grep -Eq "^Dep-age override:[[:space:]]*${lit}[[:space:]]+([-—–:]+[[:space:]]+)?[^[:space:]—–:-]" \
              || { echo "no 'Dep-age override: $offender — <advisory>' line with advisory text for an offender the checker named"; rc=1; }
          done < "$offenders"
          [ "$rc" -eq 0 ] || exit 1
          approver=$(printf '%s\n' "$BODY" | sed -n 's/^Approved-by: @\([A-Za-z0-9-]*\).*/\1/p' | head -1)
          [ "$approver" = "$actor" ] || { echo "Approved-by: @$approver does not match the approval comment's author @$actor"; exit 1; }
          echo "override honored for $(tr '\n' ' ' < "$offenders")(approved by @$actor); the follow-up issue opens at merge"
```

```yaml
# .github/workflows/dep-age-follow-up.yml (excerpt) — the follow-up, at merge.
# pull_request_target runs in the base repository's context with a
# write-capable token even for a fork PR. That is safe here only because the
# job checks out nothing and executes nothing from the PR: it reads event
# metadata and calls the API.
on:
  pull_request_target:
    types: [closed]
# ci-hygiene: paths-exempt runs once, at merge, only for a labelled PR (see
# `if:`) — there is nothing to scope by path. Concurrency is keyed on the PR
# so a re-delivered close event cannot race the first run.
concurrency:
  group: dep-age-follow-up-${{ github.event.pull_request.number }}
  cancel-in-progress: false
jobs:
  follow-up:
    if: github.event.pull_request.merged == true && contains(github.event.pull_request.labels.*.name, 'dep-age-override')
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: read
      issues: write
      pull-requests: write   # the cross-reference comment on the PR (below)
    steps:
      - name: Open the 24 h follow-up (idempotent)
        env:
          BODY: ${{ github.event.pull_request.body }}
          PR: ${{ github.event.pull_request.number }}
          PR_URL: ${{ github.event.pull_request.html_url }}
          MERGED_AT: ${{ github.event.pull_request.merged_at }}
          AUTHOR: ${{ github.event.pull_request.user.login }}
          HEAD_SHA: ${{ github.event.pull_request.head.sha }}
          # Used only for the first durable record; recovery reads that record.
          APPROVERS: ${{ vars.DEP_AGE_APPROVERS }}
          REPO: ${{ github.repository }}
          GH_TOKEN: ${{ github.token }}
        run: |
          set -euo pipefail
          APPROVERS=$(printf '%s' "$APPROVERS" | tr -d '[:space:]')
          marker="dep-age-follow-up-for-pr-$PR"
          # Freeze the approver BEFORE creating an issue. On recovery, this
          # bot-authored PR record survives roster rotation; issue bodies and
          # labels are editable and are never authority for the approver.
          gh api "repos/$REPO/issues/$PR/comments" --paginate --slurp > pr-comments.json \
            || { echo "could not read PR comments; refusing to guess"; exit 1; }
          approver=$(jq -r --arg sha "$HEAD_SHA" '[.[][] | select(.user.login == "github-actions[bot]") | .body
            | capture("^dep-age-approver: " + $sha + " @(?<a>[A-Za-z0-9-]+)$") | .a] | first // empty' pr-comments.json)
          if [ -z "$approver" ]; then
            approver=$(jq -r --arg sha "$HEAD_SHA" --arg list ",$APPROVERS," --arg author "$AUTHOR" --arg merged "$MERGED_AT" \
              '[.[][] | select((.body | test("^Dep-age approved: " + $sha + "([[:space:]]|$)"))
                               and (.user.login as $u | ($list | index("," + $u + ",")) != null)
                               and .user.login != $author and .created_at <= $merged)] | last | .user.login // empty' pr-comments.json)
            [ -n "$approver" ] || { echo "no pre-merge approval by a listed approver; refusing to guess"; exit 1; }
            gh pr comment "$PR" --repo "$REPO" --body "dep-age-approver: $HEAD_SHA @$approver"
          fi
          # Prefer the immutable PR-side link. Otherwise search up to the same
          # 1000 issues as the audit, and authenticate candidates using a bot
          # COMMENT binding this issue to this PR/head/approver. A moved body
          # marker alone never authenticates an issue, even a bot-created one.
          existing=$(jq -r --arg a "$approver" '[.[][] | select(.user.login == "github-actions[bot]") | .body
            | capture("^dep-age-follow-up: #(?<n>[0-9]+) approved-by @" + $a + "$") | .n] | first // empty' pr-comments.json)
          receipt="dep-age-origin: pr-$PR head-$HEAD_SHA approved-by @$approver"
          if [ -z "$existing" ]; then
            candidates=$(gh issue list --repo "$REPO" --state all --limit 1000 \
              --search "$marker in:body author:app/github-actions" --json number,body \
              --jq '.[] | .number') \
              || { echo "could not query follow-ups; rerun this job"; exit 1; }
            for candidate in $candidates; do
              authenticated=$(gh api "repos/$REPO/issues/$candidate/comments" --paginate --slurp \
                | jq -r --arg receipt "$receipt" '[.[][] | select(.user.login == "github-actions[bot]" and .body == $receipt)] | length') \
                || { echo "could not authenticate candidate; rerun this job"; exit 1; }
              if [ "$authenticated" -gt 0 ]; then existing="$candidate"; break; fi
            done
          fi
          case "$existing" in *[!0-9]*) echo "unexpected lookup result '$existing'"; exit 1 ;; esac
          if [ -n "$existing" ]; then
            issue="$existing"
            echo "follow-up for #$PR already exists: #$issue (marker $marker); checking its PR-side link"
          else
            # Every override line goes into the issue: each bypassed version
            # gets its own yank/advisory review, not just the first.
            overrides=$(printf '%s\n' "$BODY" | sed -n 's/^Dep-age override:[[:space:]]*/- /p')
            count=$(printf '%s\n' "$overrides" | grep -c .)
            first=$(printf '%s\n' "$overrides" | head -1 | sed 's/^- //; s/[[:space:]].*//')
            title="dep-age follow-up: $first"; [ "$count" -le 1 ] || title="$title (+$((count - 1)) more)"
            due=$(date -u -d "$MERGED_AT + 24 hours" +%Y-%m-%dT%H:%M:%SZ)      # GNU date (ubuntu runner)
            matures=$(date -u -d "$MERGED_AT + 72 hours" +%Y-%m-%dT%H:%M:%SZ)  # same format as the API's timestamps
            # `gh issue create --label` only applies an existing label; --force makes this idempotent.
            gh label create dep-age-follow-up --repo "$REPO" --color D93F0B --force \
              --description "Dependency age-gate override awaiting its follow-up (sec-01 §5)"
            issue_url=$(gh issue create --repo "$REPO" --label dep-age-follow-up --assignee "$approver" \
              --title "$title" \
              --body "$(printf '%s\nApprover: @%s\n\nOverrides honored (review each):\n%s\n\nDue: %s — 24 h review: the approver comments, starting with "Reviewed:", that for each override the advisory still stands and the version shows no yank or new advisory so far.\nMatures: %s — 72 h after merge at %s: confirm no yank or advisory and close, or roll back and close with an approver comment starting "Rolled back:".\nPR: %s\n(The audit recomputes Due/Matures from the PR merge time and takes the approver from the record this workflow froze in its own comment on that PR; editing these lines changes nothing.)\n' "$marker" "$approver" "$overrides" "$due" "$matures" "$MERGED_AT" "$PR_URL")")
            issue="${issue_url##*/}"
            # Posted before the PR link so recovery can authenticate the issue.
            # If creation succeeds but THIS comment fails, do not reuse the
            # unbound issue: a rerun creates a fresh one. Reconcile that orphan
            # manually; the audit stays red rather than trusting its marker.
            gh issue comment "$issue" --repo "$REPO" --body "$receipt"
          fi
          # Cross-reference from the PR side, authored by the workflow: the
          # audit accepts an issue as PR #N's follow-up only when PR #N carries
          # this bot comment naming it, and takes the approver of record from
          # it. Triage access cannot edit others' comments, so re-pointing the
          # issue's marker cannot forge the link and editing the issue cannot
          # change the approver. The audit matches this exact text —
          # `dep-age-follow-up: #<issue> approved-by @<login>` — so the two
          # workflows must agree on it. Posted once: a rerun that finds the
          # comment already there leaves it alone.
          link="dep-age-follow-up: #$issue approved-by @$approver"
          linked=$(gh api "repos/$REPO/issues/$PR/comments" --paginate --slurp \
            | jq -r --arg n "$issue" '[.[][] | select(.user.login == "github-actions[bot]") | .body
                                        | capture("^dep-age-follow-up: #" + $n + " approved-by @(?<a>[A-Za-z0-9-]+)$") | .a] | length') \
            || { echo "could not read PR comments; rerun this job"; exit 1; }
          [ "$linked" -gt 0 ] || gh pr comment "$PR" --repo "$REPO" --body "$link"
```

```yaml
# .github/workflows/dep-age-audit.yml (excerpt) — the nightly audit.
# Red when a follow-up missed its 24 h review (no "Reviewed:" comment BY THE
# APPROVER posted BEFORE Due: — a bot comment or a late one does not count),
# is still open a day past Matures:, was closed at maturity by anyone other
# than the approver, or was closed before Matures: without the approver's
# "Rolled back:" comment posted by the close.
# Finds issues by marker across all states, not by label, so neither a label
# removed in triage nor a premature close can hide one.
on:
  schedule:
    - cron: "17 4 * * *"
jobs:
  overdue-follow-ups:
    runs-on: ubuntu-latest
    timeout-minutes: 10   # a stalled API call must not hold a runner for hours (arch-08 §3.1)
    permissions:
      contents: read
      issues: read
      pull-requests: read   # mergedAt, head SHA, the follow-up job's own comment and the approval comment on the originating PR
    steps:
      - env:
          REPO: ${{ github.repository }}
          GH_TOKEN: ${{ github.token }}
        run: |
          now=$(date -u +%Y-%m-%dT%H:%M:%SZ); rc=0
          # Only follow-ups THIS workflow created (same author filter as the
          # creation step): a stranger's issue with a guessed marker is not audited.
          # Every open AND every closed follow-up: an invalid closure stays red
          # until it is reopened or the approver records the rollback — it must
          # not age out of the set. (1000 is gh's ceiling; a repository with
          # more dependency-age overrides than that has a different problem.)
          # Both enumerations fail CLOSED: an empty list from an API error must
          # not become a green night.
          open_ids=$(gh issue list --repo "$REPO" --state open --limit 1000 \
            --search 'dep-age-follow-up-for-pr- in:body author:app/github-actions' --json number --jq '.[].number') \
            || { echo "::error::could not enumerate open follow-ups"; exit 1; }
          closed_ids=$(gh issue list --repo "$REPO" --state closed --limit 1000 \
            --search 'dep-age-follow-up-for-pr- in:body author:app/github-actions' --json number --jq '.[].number') \
            || { echo "::error::could not enumerate closed follow-ups"; exit 1; }
          for number in $open_ids $closed_ids; do
            gh issue view "$number" --repo "$REPO" --json state,closedAt,body,comments \
              --jq '{state, closedAt, body, cs: [.comments[] | {a: .author.login, t: .createdAt, b: .body}]}' > "issue.json"
            # Deadlines and approver come from IMMUTABLE data, not the editable
            # issue body: the PR number is in the marker; its mergedAt and head
            # SHA are fixed; the approver is the one the follow-up job froze in
            # its own comment on the PR, judged against `DEP_AGE_APPROVERS` as
            # it stood at the merge. The live roster is NOT consulted here: a
            # lead who rotates off it does not turn every follow-up they
            # approved red after the fact.
            pr=$(jq -r .body issue.json | sed -n 's/^dep-age-follow-up-for-pr-\([0-9]*\)$/\1/p' | head -1)
            [ -n "$pr" ] || { echo "::error::#$number carries no dep-age-follow-up-for-pr-<n> marker line; restore it"; rc=1; continue; }
            # One checked call for all three facts: a failed lookup aborts this
            # issue's evaluation as an error instead of leaving fields empty.
            pr_meta=$(gh pr view "$pr" --repo "$REPO" --json mergedAt,author,headRefOid --jq '(.mergedAt // "") + " " + (.author.login // "") + " " + (.headRefOid // "")') \
              || { echo "::error::#$number: could not read PR #$pr (mergedAt/author/head)"; rc=1; continue; }
            read -r merged_at author head_sha <<< "$pr_meta"
            [ -n "$merged_at" ] && [ -n "$head_sha" ] \
              || { echo "::error::#$number names PR #$pr, which is not a merged PR (mergedAt/head missing)"; rc=1; continue; }
            # The marker line is editable; the workflow's own comment on the PR
            # is not (triage access cannot edit others' comments). The issue is
            # PR #N's follow-up only if PR #N carries a github-actions comment
            # `dep-age-follow-up: #<this issue number> approved-by @<login>` —
            # the exact text the follow-up job posts — and that login is the
            # approver of record. A re-pointed marker fails this and is flagged
            # rather than audited against the wrong PR. One fetch serves both
            # this lookup and the cross-check that follows.
            gh api "repos/$REPO/issues/$pr/comments" --paginate --slurp > "pr-comments.json" \
              || { echo "::error::#$number: could not read PR #$pr comments"; rc=1; continue; }
            approver=$(jq -r --arg n "$number" '[.[][] | select(.user.login == "github-actions[bot]") | .body
                                                   | capture("^dep-age-follow-up: #" + $n + " approved-by @(?<a>[A-Za-z0-9-]+)$") | .a] | first // empty' pr-comments.json)
            [ -n "$approver" ] \
              || { echo "::error::#$number claims PR #$pr but that PR carries no workflow comment naming #$number — the marker was edited; restore it"; rc=1; continue; }
            # Cross-check the frozen record against the evidence it was made
            # from: the approver posted `Dep-age approved: <merged head>` before
            # the merge and is not the PR author. Roster membership was settled
            # at the merge and is deliberately not re-tested.
            jq -e --arg sha "$head_sha" --arg who "$approver" --arg author "$author" --arg merged "$merged_at" \
                '[.[][] | select((.body | test("^Dep-age approved: " + $sha + "([[:space:]]|$)"))
                                 and .user.login == $who and $who != $author and .created_at <= $merged)] | length > 0' pr-comments.json > /dev/null \
              || { echo "::error::#$number: frozen approver @$approver has no pre-merge 'Dep-age approved: $head_sha' comment on PR #$pr"; rc=1; continue; }
            due=$(date -u -d "$merged_at + 24 hours" +%Y-%m-%dT%H:%M:%SZ)
            matures=$(date -u -d "$merged_at + 72 hours" +%Y-%m-%dT%H:%M:%SZ)
            state=$(jq -r .state issue.json); closed_at=$(jq -r '.closedAt // ""' issue.json)
            grace=$(date -u -d "$matures + 24 hours" +%Y-%m-%dT%H:%M:%SZ)
            # The review is a comment BY THE APPROVER, BEFORE Due:, that STARTS
            # with "Reviewed:" — "looking into this" is not a review. Neither
            # a review nor a rollback from before this merge can satisfy it.
            reviewed=$(jq -r --arg who "$approver" --arg merged "$merged_at" --arg due "$due" '[.cs[] | select(.a == $who and (.b | test("^Reviewed:")) and .t >= $merged and .t <= $due)] | length' issue.json)
            # A rollback note counts only when THE APPROVER wrote it, it starts
            # with "Rolled back:" (so "this was not rolled back" does not match),
            # and it was posted no later than the close.
            rolled_back=$(jq -r --arg who "$approver" --arg merged "$merged_at" --arg closed "${closed_at:-9999}" '[.cs[] | select(.a == $who and (.b | test("^Rolled back:")) and .t >= $merged and .t <= $closed)] | length' issue.json)
            if [ ! "$due" \> "$now" ] && [ "$reviewed" -eq 0 ]; then
              echo "::error::#$number missed its 24 h review: no 'Reviewed:' comment from @$approver before $due"; rc=1; fi
            if [ "$state" = "OPEN" ] && [ ! "$grace" \> "$now" ]; then
              echo "::error::#$number is still open a day past maturity ($matures)"; rc=1; fi
            # A close at or after Matures: is the maturity confirmation only
            # when the APPROVER performed it (the `closed` timeline event's
            # actor); anyone else closing it is flagged, not trusted.
            if [ "$state" = "CLOSED" ] && [ ! "$closed_at" \< "$matures" ]; then
              closer=$(gh api "repos/$REPO/issues/$number/timeline" --paginate --slurp \
                | jq -r '[.[][] | select(.event == "closed")] | last | .actor.login // empty')
              [ "$closer" = "$approver" ] \
                || { echo "::error::#$number was closed at maturity by @${closer:-unknown}, not by approver @$approver — reopen it; only the approver confirms maturity"; rc=1; }
            fi
            if [ "$state" = "CLOSED" ] && [ "$closed_at" \< "$matures" ] && [ "$rolled_back" -eq 0 ]; then
              echo "::error::#$number was closed at $closed_at, before maturity $matures, with no 'Rolled back:' comment from @$approver — reopen it, or the approver records the rollback"; rc=1; fi
          done
          exit "$rc"
```

| Language | Registry / Publish Date Source |
|----------|-------------------------------|
| Python | PyPI JSON API (`upload_time` field) |
| JavaScript/TypeScript | npm registry API (`time` field) |
| Ruby | RubyGems versions API (`created_at` field) |
| Java/Kotlin | Maven Central (`lastModified` / Sonatype API) |
| Rust | crates.io API (`created_at` field) |
| Swift | GitHub release / tag date |
| Dart | pub.dev API (`published` field) |
| Zig | Manual review of upstream commit/tag date |

## 6. Configuration Security

### Default Credentials `[P0]`

- **Never ship or deploy with default credentials.** All default passwords, API keys, and admin accounts must be changed before deployment.
- Fail loudly if default credentials are detected at startup.

### TLS/HTTPS `[P1]`

- **Enforce HTTPS for all external communication.** Redirect HTTP to HTTPS.
- Use TLS 1.2+ for all connections. Disable older TLS/SSL versions.

### Security Headers `[P1]`

- **Configure security headers on all HTTP responses:**

| Header | Value | Purpose |
|--------|-------|---------|
| `Content-Security-Policy` | Restrict sources | Prevents XSS |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` | Forces HTTPS |
| `X-Content-Type-Options` | `nosniff` | Prevents MIME sniffing |
| `X-Frame-Options` | `DENY` or `SAMEORIGIN` | Prevents clickjacking |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Controls referrer leakage |

### Debug Mode `[P2]`

- **Never enable debug mode or verbose error messages in production.**
- Log detailed errors server-side; return generic error messages to clients.
- Ensure framework debug flags are off: `DEBUG=False` (Django), `config.consider_all_requests_local = false` (Rails), `NODE_ENV=production`.

## 7. Data Protection

### Sensitive Data in Logs `[P1]`

- **Never log passwords, tokens, API keys, credit card numbers, or PII.**
- Use structured logging with field-level redaction.
- Review log output for accidental sensitive data exposure.

```python
# BAD — P1 violation
logger.info(f"User login: {username}, password: {password}")

# GOOD
logger.info("User login", extra={"username": username})
```

### PII Handling `[P2]`

- Minimize PII collection — only collect what is necessary.
- Encrypt PII at rest and in transit.
- Implement data retention policies and deletion capabilities.

### Encryption `[P2]`

- Use established encryption libraries — never implement custom cryptography.
- Encrypt sensitive data at rest (database-level or application-level encryption).
- All data in transit must use TLS.

## 8. Agent Tools & MCP Servers

Rules for servers whose caller is an AI model (MCP servers, function-calling tool
sets). Design guidance lives in
[arch-10_agent_tools_and_mcp_server_standards.md](../architecture/arch-10_agent_tools_and_mcp_server_standards.md);
the two rules below are the merge-blocking floor.

### Unfenced External Content `[P1]`

- **Never return content the server did not author to an agent without fencing it.** Fetched web pages, uploaded files, ticket and email bodies, search results, and other agents' output are untrusted and may carry prompt-injection payloads.
- Wrap each payload in a delimited `<untrusted-data source="..." kind="...">` container, escape any closing delimiter inside it and every attribute value in the opening tag (`source` is attacker-chosen), strip active content (scripts, hidden text, zero-width characters), and emit the fixed handling sentence outside the fence.
- Never interpolate untrusted content into tool descriptions, system prompts, or the server's own instructions.
- Shipped skills that use tools returning external content must teach the untrusted-data rule, and a CI test must assert that they do.

```python
# BAD — P1 violation: raw fetched content becomes part of the model's prompt
return fetch(url).text

# GOOD
return fence(fetch(url).text, source=url, kind="html-text")
```

### Ungated Agent Tool Writes `[P1]`

- **Every mutating tool is classified as a write, carries a machine-readable `writes` flag, supports `preview`, and executes only after approval.** The gate is enforced in the server or host runtime, never by prompt instruction alone.
- Deletes, bulk operations, and writes that leave the project's own data (email, third-party posts, shared branches) are never un-gated, in any session mode.
- Unattended or externally triggered sessions default to read-only. A session that has ingested untrusted content is never elevated past bounded writes.
- Every tool call is audit-logged (session, caller, tool, classification, approval decision, outcome) with field-level redaction.

```python
# BAD — P1 violation: a model can delete on its own say-so
@tool(name="kb_delete")
def kb_delete(path: str): store.delete(path)

# GOOD
@tool(name="kb_delete", writes=True)
def kb_delete(path: str, preview: bool = False):
    plan = store.plan_delete(path)
    return plan if preview else store.apply(plan)   # runtime gates non-preview calls
```

## 9. Security Tooling Reference

### Static Analysis Security Testing (SAST)

| Language | Tool | Usage |
|----------|------|-------|
| Python | `bandit` | `bandit -r src/` |
| JavaScript/TypeScript | `eslint-plugin-security` | Add to ESLint config |
| Ruby | `brakeman` | `brakeman --no-pager` |
| Java/Kotlin | SpotBugs + Find Security Bugs | Gradle/Maven plugin |
| Rust | `cargo-geiger` (unsafe audit), `clippy` | `cargo geiger`, `cargo clippy --all-targets --all-features -- -D warnings` |
| Swift | — | Use Xcode static analyzer |
| Dart | `dart analyze` | Built-in security rules |
| C/C++ | `clang-tidy` (`cert-*`, `bugprone-*`), ASan/UBSan lanes | `run-clang-tidy -p build`, `cmake --workflow --preset ci-asan-ubsan` (lang-14 §13) |

### Secrets Scanning

| Tool | Scope |
|------|-------|
| `git-secrets` | Pre-commit hook |
| `trufflehog` | Full repo/PR scan in CI (recommended, see below) |
| `detect-secrets` | Pre-commit + CI |
| GitHub Secret Scanning | Automatic (GitHub repos) |

#### Recommended CI scanner: TruffleHog `[P0]`

[TruffleHog](https://github.com/trufflesecurity/trufflehog) is the recommended
CI secret scanner. Its GitHub Action is fully free (Gitleaks' action requires a
license for v2+), it is actively maintained, and unignored findings **block
merge** per the P0 hardcoded-credentials rule above.

- **Keep verification OFF by default.** TruffleHog verifies by default, so
  pass `--no-verification` explicitly (omitting `--only-verified` is not
  enough) and report `--results=unverified,unknown`, or the unverified
  detections the scan now produces are filtered out of the blocking run.
  Verification sends detected secrets to third-party endpoints (a security
  concern in itself), needs outbound network many CI environments restrict, and
  adds latency/flakiness. An expired/rotated secret is still a finding worth
  removing from history.
- **Suppress false positives at the finest granularity that works.** Prefer an
  inline `// trufflehog:ignore` comment on the exact offending line so the rest
  of the file is still scanned (`// gitleaks:allow` is the Gitleaks
  equivalent; use both when both scanners run). A committed
  `.trufflehog-ignore` path-exclude file (consumed via `--exclude-paths`, one
  path **regex** per line) names a single artifact that provably cannot carry
  a credential; the shipped template is empty. Never exclude a whole tree
  just to silence one finding — that hides future real secrets.
  Fixture-shaped noise (UUIDs, `test-`-prefixed fakes, redaction output) is
  handled by the shape-based allowlist in §3, not by excluding `tests/`.
- **The usual exclusion candidates are where real secrets hide.** Lockfiles
  carry the registry URLs the package manager wrote, token and all; committed
  `dist/` and minified bundles are where a build-time-injected credential
  lands; test fixtures are where a pasted real credential goes unnoticed. All
  three stay scanned (§3). Their noise — lockfile hashes, hex colour codes,
  base64 font or image data — is handled by the detector's verification and
  entropy filters or an inline `trufflehog:ignore` where it appears, never by
  a path exclude.

Ship-with-standards templates: [`templates/.trufflehog-ignore`](../../templates/.trufflehog-ignore)
(allowlist with format docs) and [`templates/trufflehog.yml.example`](../../templates/trufflehog.yml.example)
(free action, verification off, merge-blocking). `setup.sh` installs the
allowlist into consumer projects; add the workflow with `setup.sh --workflow`.
Noisy, ignored scanner output is why teams disable scanning entirely — the
allowlist keeps signal high so the P0 rule stays enforced.
