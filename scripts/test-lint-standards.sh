#!/bin/bash
# Functional tests for lint-standards.sh, its output formats, and the
# lint-checks modules — the product surface consumers hit in CI.
#
# Each test builds a temp project with known conditions and asserts outcomes.
# Prioritizes the linter's JSON/SARIF output (the standards-review action's
# contract) and a representative sample of check modules.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINT="$REPO_ROOT/scripts/lint-standards.sh"
CHECKS="$REPO_ROOT/scripts/lint-checks"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS=0; FAIL=0

TMP_BASE="$(mktemp -d "${TMPDIR:-/tmp}/test-lint-standards.XXXXXX")"
trap 'rm -rf "$TMP_BASE"' EXIT

pass() { echo -e "${GREEN}✓${NC}"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}✗${NC}"; echo "  Error: $1"; FAIL=$((FAIL + 1)); }

# Pick a JSON validator (python3 preferred; fall back to node).
json_valid() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$1" 2>/dev/null
    elif command -v node >/dev/null 2>&1; then
        node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$1" 2>/dev/null
    else
        echo "no JSON validator (python3/node) available" >&2
        return 2
    fi
}

make_project() {
    local name="$1"
    local dir="$TMP_BASE/$name"
    mkdir -p "$dir"
    ( cd "$dir" && git init -q \
        && git -c user.email="t@t.local" -c user.name="T" \
               commit -q --allow-empty -m "chore: init" )
    echo "$dir"
}

echo -e "${BLUE}Testing lint-standards.sh and lint-checks modules${NC}"
echo ""

# --- Runner + output formats ------------------------------------------------

echo -n "Test 1: lint-standards.sh exists and is executable... "
if [ -x "$LINT" ]; then pass; else fail "$LINT not executable"; fi

proj=$(make_project "basic")

echo -n "Test 2: --format text runs and exits cleanly (0 or 1)... "
"$LINT" --format text "$proj" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; then pass; else fail "unexpected exit $rc"; fi

echo -n "Test 3: --format json emits valid JSON... "
"$LINT" --format json "$proj" > "$TMP_BASE/out.json" 2>/dev/null || true
if json_valid "$TMP_BASE/out.json"; then pass; else fail "invalid JSON output"; fi

echo -n "Test 4: --format json has summary.pass/warn/fail keys... "
if grep -q '"summary"' "$TMP_BASE/out.json" \
   && grep -q '"pass"' "$TMP_BASE/out.json" \
   && grep -q '"warn"' "$TMP_BASE/out.json" \
   && grep -q '"fail"' "$TMP_BASE/out.json"; then pass; else fail "missing summary keys"; fi

echo -n "Test 5: --format sarif emits valid JSON (regression: bash 3.2 unbound array)... "
"$LINT" --format sarif "$proj" > "$TMP_BASE/out.sarif" 2>/dev/null || true
if json_valid "$TMP_BASE/out.sarif"; then pass; else fail "invalid SARIF output (see #132)"; fi

echo -n "Test 6: SARIF declares version 2.1.0 and a runs array... "
if grep -q '"version": "2.1.0"' "$TMP_BASE/out.sarif" \
   && grep -q '"runs"' "$TMP_BASE/out.sarif"; then pass; else fail "SARIF missing version/runs"; fi

echo -n "Test 7: unknown --format exits non-zero with a message... "
if ! "$LINT" --format bogus "$proj" >/dev/null 2>&1; then pass; else fail "bogus format did not fail"; fi

# --- Check modules ----------------------------------------------------------

echo -n "Test 8: no-secrets module PASSes a clean project... "
clean=$(make_project "clean")
echo "print('hello')" > "$clean/app.py"
out=$(bash "$CHECKS/common/no-secrets.sh" "$clean" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 9: no-secrets module FLAGS a hardcoded AWS key... "
secret=$(make_project "secret")
# Build a valid-length AWS access key id (AKIA + 16 chars) at runtime by
# concatenation, so no key-shaped literal is committed to trip secret scanners.
aws_key="AKIA$(printf '%s' 'IOSFODNN7EXAMPLE')"   # 4 + 16 = 20 chars
printf 'aws_secret_access_key = "%s"\n' "$aws_key" > "$secret/config.py"
out=$(bash "$CHECKS/common/no-secrets.sh" "$secret" 2>/dev/null || true)
if echo "$out" | grep -qE '^(FAIL|WARN)'; then pass; else fail "expected FAIL/WARN, got: $out"; fi

echo -n "Test 10: conventional-commits module PASSes conventional history... "
cc=$(make_project "cc-good")
( cd "$cc" && git -c user.email="t@t.local" -c user.name="T" \
    commit -q --allow-empty -m "feat(api): add endpoint" )
out=$(bash "$CHECKS/common/conventional-commits.sh" "$cc" 2>/dev/null || true)
if echo "$out" | grep -qE '^(PASS|WARN)'; then pass; else fail "expected PASS/WARN, got: $out"; fi

echo -n "Test 11: every check module emits a recognized status line... "
bad=""
for m in "$CHECKS"/*/*.sh; do
    out=$(bash "$m" "$proj" 2>/dev/null || true)
    # Empty output is a failure too: a module that emits nothing is a silent
    # regression the runner would tally as zero results.
    if [ -z "$out" ] || ! echo "$out" | grep -qE '^(PASS|WARN|FAIL)'; then
        bad="$bad $(basename "$m")"
    fi
done
if [ -z "$bad" ]; then pass; else fail "modules with empty/unrecognized output:$bad"; fi

# --- Sibling scripts smoke --------------------------------------------------

echo -n "Test 12: diff-standards.sh runs on a project without .standards.yml... "
if bash "$REPO_ROOT/scripts/diff-standards.sh" "$proj" >/dev/null 2>&1; then pass; else
    # diff-standards may exit non-zero; accept as long as it doesn't crash hard (>1)
    rc=$?; if [ "$rc" -le 1 ]; then pass; else fail "diff-standards crashed (exit $rc)"; fi
fi

echo -n "Test 13: doctor.sh runs without a hard crash... "
( cd "$proj" && bash "$REPO_ROOT/scripts/doctor.sh" >/dev/null 2>&1 ); rc=$?
if [ "$rc" -le 1 ]; then pass; else fail "doctor.sh crashed (exit $rc)"; fi

# --- #182: diff-standards.sh contract ---------------------------------------

fake_standards() {
    local proj="$1"
    mkdir -p "$proj/.standards"
    ln -s "$REPO_ROOT/standards" "$proj/.standards/standards"
    ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
}

echo -n "Test 14: diff-standards.sh exits 0 without --exit-code even when changes are pending... "
proj=$(make_project "diff-pending")
fake_standards "$proj"
printf 'version: 1\nlanguages:\n  - typescript\nagents:\n  - codex\nrole: service\n' > "$proj/.standards.yml"
( cd "$proj" && bash "$REPO_ROOT/scripts/diff-standards.sh" >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 0 ]; then pass; else fail "expected 0, got $rc"; fi

echo -n "Test 15: diff-standards.sh --exit-code exits 1 when a config would be created... "
( cd "$proj" && bash "$REPO_ROOT/scripts/diff-standards.sh" --exit-code >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 1 ]; then pass; else fail "expected 1, got $rc"; fi

echo -n "Test 16: diff-standards.sh prints the sync script path (not a Make target) with no literal escapes... "
out=$( cd "$proj" && bash "$REPO_ROOT/scripts/diff-standards.sh" 2>&1 ) || true
if echo "$out" | grep -q "./.standards/scripts/sync-standards.sh" \
   && ! echo "$out" | grep -q "make sync-standards" \
   && ! echo "$out" | grep -qF '\033'; then
    pass
else
    fail "hint/escape problem in output: $out"
fi

echo -n "Test 17: diff-standards.sh --exit-code exits 0 once configs are up to date... "
( cd "$proj" && bash "$REPO_ROOT/scripts/setup.sh" --agents codex --languages typescript >/dev/null 2>&1 ) || true
( cd "$proj" && bash "$REPO_ROOT/scripts/diff-standards.sh" --exit-code >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 0 ]; then pass; else fail "expected 0 after setup, got $rc"; fi

echo -n "Test 18: diff-standards.sh --exit-code exits 0 when only the project-specific section was edited... "
# Content below the BEGIN PROJECT-SPECIFIC marker is owned by the consumer and
# preserved by sync; it must never register as drift.
printf '\n## Local notes\n\nProject-owned content.\n' >> "$proj/AGENTS.md"
( cd "$proj" && bash "$REPO_ROOT/scripts/diff-standards.sh" --exit-code >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 0 ]; then pass; else fail "project-specific section counted as drift (rc=$rc)"; fi

echo -n "Test 19: diff-standards.sh --exit-code exits 1 after the standards-owned section drifts... "
# Insert a line right after the assembly header, i.e. above the sentinel.
{ head -1 "$proj/AGENTS.md"; echo "# local drift"; tail -n +2 "$proj/AGENTS.md"; } > "$proj/AGENTS.md.tmp" \
    && mv "$proj/AGENTS.md.tmp" "$proj/AGENTS.md"
( cd "$proj" && bash "$REPO_ROOT/scripts/diff-standards.sh" --exit-code >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 1 ]; then pass; else fail "expected 1 after drift, got $rc"; fi

echo -n "Test 20: diff-standards.sh [project-root] resolves template vars against that root, not the cwd... "
alpha=$(make_project "diff-alpha")
fake_standards "$alpha"
printf '{ "name": "alpha-pkg" }\n' > "$alpha/package.json"
printf 'version: 1\nlanguages:\n  - typescript\nagents:\n  - claude-code\nrole: service\n' > "$alpha/.standards.yml"
( cd "$alpha" && bash "$REPO_ROOT/scripts/setup.sh" --agents claude-code --languages typescript >/dev/null 2>&1 ) || true
beta=$(make_project "diff-beta")
( cd "$beta" && bash "$REPO_ROOT/scripts/diff-standards.sh" --exit-code "$alpha" >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 0 ] && grep -q "alpha-pkg" "$alpha/CLAUDE.md"; then pass; else
    fail "expected 0 when run from another repo with explicit root, got $rc"
fi

echo -n "Test 21: diff-standards.sh refuses to run from inside .standards/... "
inside=$(make_project "diff-inside")
mkdir -p "$inside/.standards"
( cd "$inside/.standards" && git init -q \
    && git -c user.email="t@t.local" -c user.name="T" commit -q --allow-empty -m "chore: init" )
out=$( cd "$inside/.standards" && bash "$REPO_ROOT/scripts/diff-standards.sh" 2>&1 ); rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "inside"; then pass; else fail "expected refusal (rc=$rc): $out"; fi

echo -n "Test 22: diff-standards.sh rejects an unknown option with exit 2... "
( cd "$proj" && bash "$REPO_ROOT/scripts/diff-standards.sh" --bogus >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 2 ]; then pass; else fail "expected 2, got $rc"; fi

# --- Rust check modules -----------------------------------------------------

echo -n "Test 23: rust/clippy-ci PASSes when CI runs clippy with -D warnings... "
rs=$(make_project "rust-clippy-good")
mkdir -p "$rs/.github/workflows"
cat > "$rs/.github/workflows/ci.yml" <<'EOF'
jobs:
  lint:
    steps:
      - run: cargo clippy --workspace --all-targets --all-features -- -D warnings
EOF
out=$(bash "$CHECKS/rust/clippy-ci.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS rust/clippy-ci'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 24: rust/clippy-ci WARNs when clippy runs without -D warnings... "
rs=$(make_project "rust-clippy-warn")
mkdir -p "$rs/.github/workflows"
printf 'jobs:\n  lint:\n    steps:\n      - run: cargo clippy --all-targets\n' > "$rs/.github/workflows/ci.yml"
out=$(bash "$CHECKS/rust/clippy-ci.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN rust/clippy-ci'; then pass; else fail "expected WARN, got: $out"; fi

echo -n "Test 25: rust/clippy-ci FAILs when no CI workflow runs clippy... "
rs=$(make_project "rust-clippy-none")
mkdir -p "$rs/.github/workflows"
printf 'jobs:\n  test:\n    steps:\n      - run: cargo test\n' > "$rs/.github/workflows/ci.yml"
out=$(bash "$CHECKS/rust/clippy-ci.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL rust/clippy-ci'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 26: rust/deny-config PASSes with a deny.toml license allow-list... "
rs=$(make_project "rust-deny-good")
printf '[licenses]\nallow = ["MIT", "Apache-2.0"]\n' > "$rs/deny.toml"
out=$(bash "$CHECKS/rust/deny-config.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS rust/deny-config'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 27: rust/deny-config WARNs when deny.toml has no license allow-list... "
rs=$(make_project "rust-deny-nolicense")
printf '[advisories]\nvulnerability = "deny"\n' > "$rs/deny.toml"
out=$(bash "$CHECKS/rust/deny-config.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN rust/deny-config'; then pass; else fail "expected WARN, got: $out"; fi

echo -n "Test 28: rust/deny-config FAILs when deny.toml is missing... "
rs=$(make_project "rust-deny-missing")
out=$(bash "$CHECKS/rust/deny-config.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL rust/deny-config'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 29: rust/toolchain-pin PASSes when toolchain, rust-version and CI agree... "
rs=$(make_project "rust-pin-good")
printf '[toolchain]\nchannel = "1.99.0"\ncomponents = ["clippy", "rustfmt"]\n' > "$rs/rust-toolchain.toml"
printf '[package]\nname = "demo"\nversion = "0.1.0"\nedition = "2021"\nrust-version = "1.99"\n' > "$rs/Cargo.toml"
mkdir -p "$rs/.github/workflows"
cat > "$rs/.github/workflows/ci.yml" <<'EOF'
jobs:
  test:
    steps:
      - uses: dtolnay/rust-toolchain@master
        with:
          toolchain: 1.99.0
      - run: cargo test
EOF
out=$(bash "$CHECKS/rust/toolchain-pin.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS rust/toolchain-pin'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 30: rust/toolchain-pin FAILs when CI pins a different toolchain... "
rs=$(make_project "rust-pin-ci-drift")
printf '[toolchain]\nchannel = "1.99.0"\n' > "$rs/rust-toolchain.toml"
printf '[package]\nname = "demo"\nrust-version = "1.99"\n' > "$rs/Cargo.toml"
mkdir -p "$rs/.github/workflows"
printf 'jobs:\n  test:\n    steps:\n      - uses: dtolnay/rust-toolchain@1.98.0\n' > "$rs/.github/workflows/ci.yml"
out=$(bash "$CHECKS/rust/toolchain-pin.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL rust/toolchain-pin'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 31: rust/toolchain-pin FAILs when rust-version is newer than the pinned toolchain... "
rs=$(make_project "rust-pin-msrv-newer")
printf '[toolchain]\nchannel = "1.98.0"\n' > "$rs/rust-toolchain.toml"
printf '[package]\nname = "demo"\nrust-version = "1.99"\n' > "$rs/Cargo.toml"
out=$(bash "$CHECKS/rust/toolchain-pin.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL rust/toolchain-pin'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 32: rust/toolchain-pin WARNs when rust-toolchain.toml is missing... "
rs=$(make_project "rust-pin-missing")
printf '[package]\nname = "demo"\nrust-version = "1.99"\n' > "$rs/Cargo.toml"
out=$(bash "$CHECKS/rust/toolchain-pin.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN rust/toolchain-pin'; then pass; else fail "expected WARN, got: $out"; fi

echo -n "Test 33: rust/ffi-no-unwrap PASSes when facade files are panic-free... "
rs=$(make_project "rust-ffi-good")
mkdir -p "$rs/src"
cat > "$rs/src/ffi.rs" <<'EOF'
#![deny(clippy::disallowed_methods)]
// unwrap() in this comment must not count
#[no_mangle]
pub extern "C" fn demo_parse(input: *const u8) -> i32 {
    match parse(input) { Ok(_) => 0, Err(_) => -1 }
}
EOF
printf 'pub fn helper() -> i32 { Some(1).unwrap() }\n' > "$rs/src/lib.rs"
out=$(bash "$CHECKS/rust/ffi-no-unwrap.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS rust/ffi-no-unwrap'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 34: rust/ffi-no-unwrap FAILs on unwrap()/expect() in ffi.rs or wasm.rs... "
rs=$(make_project "rust-ffi-bad")
mkdir -p "$rs/src"
printf 'pub extern "C" fn demo() -> i32 { parse().unwrap() }\n' > "$rs/src/ffi.rs"
printf '#[wasm_bindgen]\npub fn demo() -> u32 { parse().expect("boom") }\n' > "$rs/src/wasm.rs"
out=$(bash "$CHECKS/rust/ffi-no-unwrap.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL rust/ffi-no-unwrap' && echo "$out" | grep -q 'ffi.rs' && echo "$out" | grep -q 'wasm.rs'; then
    pass
else
    fail "expected FAIL naming both files, got: $out"
fi

echo -n "Test 35: rust/ffi-no-unwrap PASSes when no facade files exist... "
rs=$(make_project "rust-ffi-none")
mkdir -p "$rs/src"; printf 'fn main() {}\n' > "$rs/src/main.rs"
out=$(bash "$CHECKS/rust/ffi-no-unwrap.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS rust/ffi-no-unwrap'; then pass; else fail "expected PASS, got: $out"; fi

# --- Swift check modules ----------------------------------------------------

echo -n "Test 36: swift/swift-format-config PASSes with a .swift-format file... "
sw=$(make_project "swift-format-good")
printf '{ "version": 1, "lineLength": 120 }\n' > "$sw/.swift-format"
out=$(bash "$CHECKS/swift/swift-format-config.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS swift/swift-format-config'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 37: swift/swift-format-config WARNs when only .swiftlint.yml exists... "
sw=$(make_project "swift-format-swiftlint-only")
printf 'disabled_rules: []\n' > "$sw/.swiftlint.yml"
out=$(bash "$CHECKS/swift/swift-format-config.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN swift/swift-format-config'; then pass; else fail "expected WARN, got: $out"; fi

echo -n "Test 38: swift/swift-format-config FAILs with no formatter config... "
sw=$(make_project "swift-format-none")
out=$(bash "$CHECKS/swift/swift-format-config.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL swift/swift-format-config'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 39: swift/package-resolved PASSes when Package.resolved is committed... "
sw=$(make_project "swift-resolved-good")
printf '// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: "Demo", dependencies: [.package(url: "https://example.com/x", from: "1.0.0")])\n' > "$sw/Package.swift"
printf '{ "pins": [], "version": 3 }\n' > "$sw/Package.resolved"
( cd "$sw" && git add Package.swift Package.resolved \
    && git -c user.email="t@t.local" -c user.name="T" commit -q -m "chore: add package" )
out=$(bash "$CHECKS/swift/package-resolved.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS swift/package-resolved'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 40: swift/package-resolved FAILs when Package.resolved is gitignored... "
sw=$(make_project "swift-resolved-ignored")
printf '// swift-tools-version: 6.0\nlet package = Package(name: "Demo", dependencies: [.package(url: "https://example.com/x", from: "1.0.0")])\n' > "$sw/Package.swift"
printf '{ "pins": [] }\n' > "$sw/Package.resolved"
printf 'Package.resolved\n' > "$sw/.gitignore"
( cd "$sw" && git add Package.swift .gitignore \
    && git -c user.email="t@t.local" -c user.name="T" commit -q -m "chore: add package" )
out=$(bash "$CHECKS/swift/package-resolved.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL swift/package-resolved'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 41: swift/package-resolved FAILs when an executable has dependencies but no Package.resolved... "
sw=$(make_project "swift-resolved-missing")
printf '// swift-tools-version: 6.0\nlet package = Package(name: "Demo", dependencies: [.package(url: "https://example.com/x", from: "1.0.0")], targets: [.executableTarget(name: "Demo")])\n' > "$sw/Package.swift"
out=$(bash "$CHECKS/swift/package-resolved.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL swift/package-resolved'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 42: swift/package-resolved PASSes for a dependency-free package... "
sw=$(make_project "swift-resolved-nodeps")
printf '// swift-tools-version: 6.0\nlet package = Package(name: "Demo", targets: [.target(name: "Demo")])\n' > "$sw/Package.swift"
out=$(bash "$CHECKS/swift/package-resolved.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS swift/package-resolved'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 43: swift/warnings-as-errors PASSes when CI passes -warnings-as-errors... "
sw=$(make_project "swift-wae-ci")
mkdir -p "$sw/.github/workflows"
printf 'jobs:\n  test:\n    steps:\n      - run: swift build -Xswiftc -warnings-as-errors\n' > "$sw/.github/workflows/ci.yml"
out=$(bash "$CHECKS/swift/warnings-as-errors.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS swift/warnings-as-errors'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 44: swift/warnings-as-errors PASSes when project.yml sets SWIFT_TREAT_WARNINGS_AS_ERRORS... "
sw=$(make_project "swift-wae-xcodegen")
printf 'settings:\n  base:\n    SWIFT_TREAT_WARNINGS_AS_ERRORS: YES\n' > "$sw/project.yml"
out=$(bash "$CHECKS/swift/warnings-as-errors.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS swift/warnings-as-errors'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 45: swift/warnings-as-errors FAILs when nothing enables it... "
sw=$(make_project "swift-wae-none")
mkdir -p "$sw/.github/workflows"
printf 'jobs:\n  test:\n    steps:\n      - run: swift test\n' > "$sw/.github/workflows/ci.yml"
out=$(bash "$CHECKS/swift/warnings-as-errors.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL swift/warnings-as-errors'; then pass; else fail "expected FAIL, got: $out"; fi

# --- Runner wiring for the new language directories --------------------------

echo -n "Test 46: runner activates rust/ and swift/ checks from .standards.yml languages... "
wired=$(make_project "wired-rust-swift")
printf 'version: 1\nlanguages:\n  - rust\n  - swift\n' > "$wired/.standards.yml"
"$LINT" --format json "$wired" > "$TMP_BASE/wired.json" 2>/dev/null || true
if grep -q '"check": "rust/clippy-ci"' "$TMP_BASE/wired.json" \
   && grep -q '"check": "rust/toolchain-pin"' "$TMP_BASE/wired.json" \
   && grep -q '"check": "swift/swift-format-config"' "$TMP_BASE/wired.json" \
   && grep -q '"check": "swift/package-resolved"' "$TMP_BASE/wired.json"; then
    pass
else
    fail "rust/ or swift/ checks missing from JSON output"
fi

# --- Review follow-ups (#207): precision fixes to the rust/ and swift/ modules

echo -n "Test 47: rust/clippy-ci FAILs when only a Makefile runs clippy and no CI definition exists... "
rs=$(make_project "rust-clippy-makefile-only")
printf 'lint:\n\tcargo clippy --all-targets -- -D warnings\n' > "$rs/Makefile"
out=$(bash "$CHECKS/rust/clippy-ci.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL rust/clippy-ci'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 48: rust/clippy-ci PASSes when CI delegates to a Makefile that runs clippy -D warnings... "
rs=$(make_project "rust-clippy-via-make")
mkdir -p "$rs/.github/workflows"
printf 'jobs:\n  lint:\n    steps:\n      - run: make lint\n' > "$rs/.github/workflows/ci.yml"
printf 'lint:\n\tcargo clippy --all-targets -- -D warnings\n' > "$rs/Makefile"
out=$(bash "$CHECKS/rust/clippy-ci.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS rust/clippy-ci'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 49: rust/deny-config PASSes with single-quoted TOML license strings... "
rs=$(make_project "rust-deny-single-quotes")
printf "[licenses]\nallow = ['MIT', 'Apache-2.0']\n" > "$rs/deny.toml"
out=$(bash "$CHECKS/rust/deny-config.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS rust/deny-config.*2 license'; then pass; else fail "expected PASS with 2 licenses, got: $out"; fi

echo -n "Test 50: rust/toolchain-pin WARNs when the channel lacks a patch component... "
rs=$(make_project "rust-pin-no-patch")
printf '[toolchain]\nchannel = "1.99"\n' > "$rs/rust-toolchain.toml"
printf '[package]\nname = "demo"\nrust-version = "1.99"\n' > "$rs/Cargo.toml"
out=$(bash "$CHECKS/rust/toolchain-pin.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN rust/toolchain-pin.*major.minor.patch'; then pass; else fail "expected WARN about patch component, got: $out"; fi

echo -n "Test 51: rust/toolchain-pin FAILs when .gitlab-ci.yml pins a different toolchain... "
rs=$(make_project "rust-pin-gitlab-drift")
printf '[toolchain]\nchannel = "1.99.0"\n' > "$rs/rust-toolchain.toml"
printf '[package]\nname = "demo"\nrust-version = "1.99"\n' > "$rs/Cargo.toml"
printf 'test:\n  script:\n    - rustup default 1.98.0\n    - cargo test\n' > "$rs/.gitlab-ci.yml"
out=$(bash "$CHECKS/rust/toolchain-pin.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL rust/toolchain-pin.*gitlab-ci.yml'; then pass; else fail "expected FAIL naming .gitlab-ci.yml, got: $out"; fi

echo -n "Test 52: rust/ffi-no-unwrap FAILs even when the unwrap line carries an allow() annotation... "
rs=$(make_project "rust-ffi-allow-text")
mkdir -p "$rs/src"
printf '#[allow(clippy::unwrap_used)] pub extern "C" fn demo() -> i32 { parse().unwrap() }\n' > "$rs/src/ffi.rs"
out=$(bash "$CHECKS/rust/ffi-no-unwrap.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL rust/ffi-no-unwrap'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 53: swift/swift-format-config WARNs when only .swift-format.json exists (not auto-discovered)... "
sw=$(make_project "swift-format-json-only")
printf '{ "version": 1 }\n' > "$sw/.swift-format.json"
out=$(bash "$CHECKS/swift/swift-format-config.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN swift/swift-format-config.*--configuration'; then pass; else fail "expected WARN, got: $out"; fi

echo -n "Test 54: swift/package-resolved WARNs (not FAIL) for a library with dependencies and no CI build... "
sw=$(make_project "swift-resolved-library")
printf '// swift-tools-version: 6.0\nlet package = Package(name: "Demo", dependencies: [.package(url: "https://example.com/x", from: "1.0.0")], targets: [.target(name: "Demo")])\n' > "$sw/Package.swift"
out=$(bash "$CHECKS/swift/package-resolved.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN swift/package-resolved'; then pass; else fail "expected WARN, got: $out"; fi

echo -n "Test 55: swift/package-resolved FAILs for a library with dependencies and a CI build but no lockfile... "
mkdir -p "$sw/.github/workflows"
printf 'jobs:\n  test:\n    steps:\n      - run: swift test\n' > "$sw/.github/workflows/ci.yml"
out=$(bash "$CHECKS/swift/package-resolved.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL swift/package-resolved'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 56: swift/warnings-as-errors FAILs when only an unrelated C -Werror flag exists... "
sw=$(make_project "swift-wae-cflags")
printf 'CFLAGS = -Wall -Werror\n\nbuild:\n\tswift build\n' > "$sw/Makefile"
out=$(bash "$CHECKS/swift/warnings-as-errors.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL swift/warnings-as-errors'; then pass; else fail "expected FAIL, got: $out"; fi

echo ""
if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}All $PASS tests passed!${NC}"
    exit 0
else
    echo -e "${RED}$FAIL of $((PASS + FAIL)) tests failed.${NC}"
    exit 1
fi
