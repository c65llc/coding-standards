---
title: "72-Hour Age Gate: Our Response to the Axios Supply Chain Attack"
date: 2026-03-31
authors:
  - name: C65 LLC
---

At 00:21 UTC on March 31, 2026, a compromised npm maintainer account published `axios@1.14.1` -- a trojaned version of the most popular JavaScript HTTP client, a package downloaded over [100 million times per week](https://snyk.io/blog/axios-npm-package-compromised-supply-chain-attack-delivers-cross-platform/). Thirty-nine minutes later, `axios@0.30.4` followed. Both versions injected a hidden dependency, `plain-crypto-js@4.2.1`, whose sole purpose was to drop a cross-platform remote access trojan onto developer machines ([Socket](https://socket.dev/blog/axios-npm-package-compromised), [The Hacker News](https://thehackernews.com/2026/03/axios-supply-chain-attack-pushes-cross.html)).

Today we are adding a **mandatory 72-hour (3-day) dependency age gate** to every language standard in this framework.

## What Happened

The attacker compromised the npm credentials of the primary Axios maintainer, bypassing the project's GitHub Actions CI/CD pipeline entirely ([StepSecurity](https://www.stepsecurity.io/blog/axios-compromised-on-npm-malicious-versions-drop-remote-access-trojan)). According to Socket's analysis, the malicious dependency was staged 18 hours in advance, three separate RAT payloads were pre-built for macOS, Windows, and Linux, and both release branches were hit within 39 minutes of each other ([Socket](https://socket.dev/blog/axios-npm-package-compromised)).

The dropper used a dual-layer obfuscation scheme -- reversed Base64 encoding plus XOR cipher -- to evade static analysis ([Snyk](https://snyk.io/blog/axios-npm-package-compromised-supply-chain-attack-delivers-cross-platform/)). On install, npm's `postinstall` hook executed automatically, detected the developer's OS, and downloaded a platform-specific RAT from a command-and-control server. The payloads beaconed to C2 every 60 seconds, accepting commands for arbitrary code execution, credential harvesting, SSH key exfiltration, and filesystem enumeration ([Socket](https://socket.dev/blog/axios-npm-package-compromised)).

The malicious versions were live for roughly **two to three hours** before detection and removal. [Socket's scanner flagged the compromise within about 6 minutes](https://socket.dev/blog/axios-npm-package-compromised), but the npm registry take-down took longer. Any `npm install` or CI pipeline that ran during that window -- without a lockfile, or with loose version ranges -- pulled the trojan automatically.

For the full breakdown, see the [Malwarebytes write-up](https://www.malwarebytes.com/blog/news/2026/03/axios-supply-chain-attack-chops-away-at-npm-trust). Additional technical analysis is available from [Huntress](https://www.huntress.com/blog/supply-chain-compromise-axios-npm-package), [Wiz](https://www.wiz.io/blog/axios-npm-compromised-in-supply-chain-attack), and [SANS](https://www.sans.org/blog/axios-npm-supply-chain-compromise-malicious-packages-remote-access-trojan).

## Why a 72-Hour Age Gate

The axios attack was detected and reverted within hours. Most supply chain attacks follow this pattern: a malicious version is published, the community detects it, and the registry pulls it -- usually within 1-3 days. A 72-hour waiting period before adopting any new dependency version means your team never installs a package during that critical window.

This is not a novel idea. Google's [SLSA framework](https://slsa.dev/) and the OpenSSF [Scorecard project](https://securityscorecards.dev/) both recommend evaluating package freshness as a risk signal. We are making it a hard rule.

**What the age gate catches:**

- **Compromised maintainer accounts** (like axios) -- malicious versions are typically reverted within hours to days
- **Typosquatting packages** -- most are flagged and removed quickly once published
- **Accidental secret leaks** -- maintainers who publish credentials in a release and yank it

**What it does not catch:**

- Long-lived, subtle backdoors that evade detection for weeks (these require deeper supply chain controls like reproducible builds and code review of dependencies)

## What Changed in Our Standards

We updated three layers of documentation:

### Core Standards (`core-standards.md`)

A new **Dependency Age Gate** subsection under Dependency Management:

> All 3rd-party dependency versions must be at least 3 days old before adoption. Do not upgrade to or add a dependency version published less than 72 hours ago. CI should enforce age verification against the registry publish date.

### Security Standards (`sec-01`, Section 5)

A new **P1-severity rule** under Dependency & Supply Chain Security. P1 means this is merge-blocking -- CI must fail if a dependency version is younger than 3 days. The rule includes:

- A registry API reference table covering PyPI, npm, crates.io, RubyGems, Maven Central, pub.dev, Swift packages, and Zig
- An exception process for emergency security patches (team lead approval + documented justification + 24-hour follow-up review)

### Language Standards (`lang-01` through `lang-10`)

The core language standards (`lang-01` through `lang-10`) now include an **Age Gate** bullet in their Package Management sections, with the language-specific registry to check and a cross-reference to the full exception process in `sec-01`. Ruby on Rails (`lang-11`) inherits the rule from its Ruby base standard (`lang-10`). Remaining standards, including Go and Elixir, will adopt the same rule in their next revision.

## Enforcing It in CI

The registry publish date is available via API for every major ecosystem:

```bash
# npm - check publish date of a specific version
curl -s https://registry.npmjs.org/axios | jq '.time["1.14.1"]'

# PyPI
curl -s https://pypi.org/pypi/requests/json | jq '.releases["2.31.0"][0].upload_time'

# crates.io
curl -s https://crates.io/api/v1/crates/serde/versions | jq '.versions[0].created_at'

# RubyGems
curl -s https://rubygems.org/api/v1/versions/rails.json | jq '.[0].created_at'
```

A CI check that compares lockfile versions against registry timestamps is straightforward to build. We recommend running it as a required status check on every PR that modifies a lockfile.

## The Exception Process

Sometimes you genuinely need a fresh dependency version -- typically a critical CVE fix. The exception requires:

1. **Explicit approval** from a team lead or security owner
2. **Documented justification** in the PR description explaining why the bypass is necessary
3. **A follow-up review** within 24 hours to confirm the version was not subsequently reverted or flagged

This keeps the gate meaningful without blocking legitimate emergency responses.

## What You Should Do Now

If you use Coding Standards in your projects, run `make sync-standards` to pull the updated rules. If you maintain your own standards, consider adopting the 72-hour age gate -- the axios attack demonstrated that even the most trusted packages in the ecosystem can be weaponized overnight.

For the axios incident specifically: if you ran `npm install` between 00:21 and ~03:29 UTC on March 31, 2026 without a committed lockfile, check whether `axios@1.14.1` or `axios@0.30.4` was installed. If so, assume compromise and rotate all credentials on the affected machine.

---

*See the full rule in [sec-01: Security Standards](/standards/security/sec-01_security_standards/) and the updated [core standards](/standards/shared/core-standards/).*
