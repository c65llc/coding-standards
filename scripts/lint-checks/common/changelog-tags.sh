#!/bin/bash
# Check: every released CHANGELOG heading has a matching git tag (proc-02 §5)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN
#
# A changelog that lists 0.1.4 and 0.1.5 while only v0.1.2/v0.1.3 exist as tags
# (and package.json still says 0.1.3) means the release process stopped at the
# prose: nothing is reproducible from the "released" versions. This check reads
# the Keep-a-Changelog release headings and asserts each one is a tag.
#
#   - Headings: `## [1.2.3] - 2026-01-01`, `## 1.2.3 (2026-01-01)`, `## v1.2.3`,
#     with an optional prerelease/build suffix and an optional `[YANKED]`.
#     `## [Unreleased]` (any case) is skipped.
#   - Tags: `v<version>` or `<version>` by default; `.standards.yml`
#     `release.tag_prefix` makes one prefix authoritative.
#   - Location: CHANGELOG.md / CHANGELOG / CHANGES.md / HISTORY.md at the root,
#     or `release.changelog` in .standards.yml (a declared file that is missing
#     fails closed).
#   - Manifest drift (WARN): when any root package.json / Cargo.toml /
#     pyproject.toml carries a version that is not the latest released heading
#     (SemVer precedence), the manifest was not bumped in the release commit.
#     Every root manifest with a static version is checked, not just the first.
#   - Release in flight (WARN): exactly the NEWEST heading untagged, every
#     older one tagged — a release PR promotes [Unreleased] and the tag is cut
#     after merge, so this state exists legitimately for a short while. Two or
#     more untagged headings, or an older untagged heading while newer ones
#     are tagged (the forgotten-tag pattern from the consumer survey), FAIL.
#   - Shallow clone (WARN, never PASS or FAIL on a missing tag): a `--depth`
#     clone only carries the tags that point inside the fetched history, so a
#     heading without a visible tag is unverifiable rather than untagged. The
#     check says so — actions/checkout needs `fetch-depth: 0` or
#     `fetch-tags: true`. Tags that ARE visible still verify their headings.
#
# Gate rules (proc-05 § 7, scripts/lint-checks/README.md "Writing a gate"):
#   - self-tests the heading parser, the tag matcher and the manifest readers
#     on every run; a rotted detector reports FAIL, never a clean result
#   - fails closed on a declared changelog that is missing or empty
#   - bash 3.2 + POSIX awk/sed/sort only, so macOS and Linux agree

PROJECT_ROOT="${1:-.}"

CHECK_NAME="changelog-tags"
DEFAULT_LOCATIONS="CHANGELOG.md CHANGELOG CHANGES.md HISTORY.md changelog.md"
MAX_LISTED=4
SEMVER_ERE='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'

# ---------------------------------------------------------------------------
# Heading parser — emits one version per released `## ...` heading, in file
# order, with the surrounding `[ ]`, a leading `v`/`V`, the date and any
# `[YANKED]` marker stripped. Unreleased headings never appear in the output.
# ---------------------------------------------------------------------------
extract_versions() {
    awk '
    /^## / {
        s = substr($0, 4)
        sub(/^[[:space:]]+/, "", s)
        sub(/^\[/, "", s)
        # Cut at the end of the version token: closing bracket, space, "(" or ":".
        if (match(s, /[] (:]/)) s = substr(s, 1, RSTART - 1)
        sub(/^[vV]/, "", s)
        if (s == "") next
        if (tolower(s) == "unreleased") next
        if (s ~ /^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$/) print s
    }'
}

# newest_version < versions → the highest version in the list under SemVer
# precedence (semver.org §11): major/minor/patch compared numerically (so
# `1.10.0` > `1.9.0`), a prerelease ranks below its release, prerelease
# identifiers are compared one by one — numeric ones numerically (`rc.10` >
# `rc.2`), numeric below alphanumeric, a longer identifier list winning a tie —
# and build metadata is ignored. POSIX awk only.
newest_version() {
    awk '
    function isnum(s) { return s ~ /^[0-9]+$/ }
    # cmpnum(a, b): compare two digit strings as integers of any size — strip
    # leading zeros, then shorter is smaller, then lexical. No float coercion,
    # so components beyond 2^53 stay distinct.
    function cmpnum(a, b) {
        sub(/^0+/, "", a); sub(/^0+/, "", b)
        if (length(a) != length(b)) return (length(a) < length(b)) ? -1 : 1
        if (a == b) return 0
        return (a "" < b "") ? -1 : 1
    }
    # parse(v, out): out[1..3] = core components, out["pre"] = prerelease or ""
    function parse(v, out,    d) {
        sub(/\+.*$/, "", v)
        d = index(v, "-")
        if (d > 0) { split(substr(v, 1, d - 1), out, "."); out["pre"] = substr(v, d + 1) }
        else { split(v, out, "."); out["pre"] = "" }
    }
    # cmpver(a, b): negative when a < b, 0 when equal, positive when a > b
    function cmpver(a, b,    A, B, i, na, nb, pa, pb, an, bn, r) {
        parse(a, A); parse(b, B)
        for (i = 1; i <= 3; i++) { r = cmpnum(A[i], B[i]); if (r != 0) return r }
        if (A["pre"] == "" && B["pre"] == "") return 0
        if (A["pre"] == "") return 1
        if (B["pre"] == "") return -1
        na = split(A["pre"], pa, "."); nb = split(B["pre"], pb, ".")
        for (i = 1; i <= na && i <= nb; i++) {
            an = isnum(pa[i]); bn = isnum(pb[i])
            if (an && bn) { r = cmpnum(pa[i], pb[i]); if (r != 0) return r }
            else if (an) return -1
            else if (bn) return 1
            else if (pa[i] != pb[i]) return (pa[i] "" < pb[i] "") ? -1 : 1
        }
        if (na != nb) return (na < nb) ? -1 : 1
        return 0
    }
    NF > 0 { if (!seen || cmpver($0, best) > 0) best = $0; seen = 1 }
    END { if (seen) print best }'
}

# tag_for <version> <tags-newline-list> <prefix-or-__DEFAULT__> → prints the
# matching tag name, or returns 1 when none matches
tag_for() {
    local version="$1" tags="$2" prefix="$3"
    if [ "$prefix" = "__DEFAULT__" ]; then
        if printf '%s\n' "$tags" | grep -Fxq -- "v$version"; then printf 'v%s\n' "$version"; return 0; fi
        if printf '%s\n' "$tags" | grep -Fxq -- "$version"; then printf '%s\n' "$version"; return 0; fi
        return 1
    fi
    if printf '%s\n' "$tags" | grep -Fxq -- "$prefix$version"; then printf '%s%s\n' "$prefix" "$version"; return 0; fi
    return 1
}

# ---------------------------------------------------------------------------
# Manifest readers — root manifests only; each prints a version or nothing.
# ---------------------------------------------------------------------------
manifest_version_package_json() {
    # The ROOT object's "version" string, whatever the formatting (pretty or
    # one line) and wherever it sits among the keys. A tiny JSON walker tracks
    # string state and nesting depth, so a nested `"version"` inside e.g.
    # `"releaseConfig": {…}` or a dependency table is never mistaken for it.
    awk '
    { buf = buf $0 "\n" }
    END {
        n = length(buf); depth = 0; instr = 0; esc = 0; tok = ""; key = ""; want = 0
        for (i = 1; i <= n; i++) {
            c = substr(buf, i, 1)
            if (instr) {
                if (esc) { esc = 0; tok = tok c; continue }
                if (c == "\\") { esc = 1; tok = tok c; continue }
                if (c == "\"") {
                    instr = 0
                    if (depth == 1) {
                        if (want) { print tok; exit }
                        key = tok
                    }
                    continue
                }
                tok = tok c; continue
            }
            if (c == "\"") { instr = 1; tok = ""; continue }
            if (c == "{" || c == "[") { depth++; key = ""; want = 0; continue }
            if (c == "}" || c == "]") { depth--; key = ""; want = 0; continue }
            if (c == ":") { if (depth == 1 && key == "version") want = 1; key = ""; continue }
            if (c == ",") { key = ""; want = 0; continue }
        }
    }' "$1"
}

manifest_version_cargo_toml() {
    # `version = "x"` inside [package] or [workspace.package]; a
    # `version.workspace = true` member defers to the workspace and prints nothing.
    awk '
    /^[[:space:]]*\[/ { sect = $0; sub(/#.*$/, "", sect); gsub(/[[:space:]]/, "", sect); next }
    # `version = …` inside the section, or the dotted-key spelling of the same
    # table: top-level `package.version = …`, or `package.version = …` under
    # `[workspace]` (TOML dotted keys define the same nested table).
    ((sect == "[package]" || sect == "[workspace.package]") && /^[[:space:]]*version[[:space:]]*=/) ||
    ((sect == "" || sect == "[workspace]") && /^[[:space:]]*package\.version[[:space:]]*=/) {
        line = $0
        sub(/^[^=]*=[[:space:]]*/, "", line)
        # TOML basic ("…") and literal ('"'"'…'"'"') strings are both legal here.
        if (match(line, /"[^"]*"/)) { print substr(line, RSTART + 1, RLENGTH - 2); exit }
        if (match(line, /'"'"'[^'"'"']*'"'"'/)) { print substr(line, RSTART + 1, RLENGTH - 2); exit }
    }' "$1"
}

manifest_version_pyproject() {
    # `version = "x"` under [project] or [tool.poetry]; `dynamic = ["version"]`
    # projects have no static version and print nothing.
    awk '
    /^[[:space:]]*\[/ { sect = $0; sub(/#.*$/, "", sect); gsub(/[[:space:]]/, "", sect); next }
    # `version = …` inside the section, or the dotted-key spelling: top-level
    # `project.version` / `tool.poetry.version`, or `poetry.version` under
    # `[tool]`.
    ((sect == "[project]" || sect == "[tool.poetry]") && /^[[:space:]]*version[[:space:]]*=/) ||
    (sect == "" && /^[[:space:]]*(project|tool\.poetry)\.version[[:space:]]*=/) ||
    (sect == "[tool]" && /^[[:space:]]*poetry\.version[[:space:]]*=/) {
        line = $0
        sub(/^[^=]*=[[:space:]]*/, "", line)
        if (match(line, /"[^"]*"/)) { print substr(line, RSTART + 1, RLENGTH - 2); exit }
        if (match(line, /'"'"'[^'"'"']*'"'"'/)) { print substr(line, RSTART + 1, RLENGTH - 2); exit }
    }' "$1"
}

# root_manifest_versions <root> → one "<file> <version>" line per root manifest
# that carries a static version (a polyglot root may have several; every one
# is checked, so a stale Cargo.toml is not hidden by a current package.json)
root_manifest_versions() {
    local root="$1" v
    if [ -f "$root/package.json" ]; then
        v=$(manifest_version_package_json "$root/package.json")
        [ -n "$v" ] && printf 'package.json %s\n' "$v"
    fi
    if [ -f "$root/Cargo.toml" ]; then
        v=$(manifest_version_cargo_toml "$root/Cargo.toml")
        [ -n "$v" ] && printf 'Cargo.toml %s\n' "$v"
    fi
    if [ -f "$root/pyproject.toml" ]; then
        v=$(manifest_version_pyproject "$root/pyproject.toml")
        [ -n "$v" ] && printf 'pyproject.toml %s\n' "$v"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Self-test — the detector must prove it still detects before it may report
# ---------------------------------------------------------------------------
self_test() {
    local fixture got want tags t tmp

    fixture='# Changelog

## [Unreleased]

- pending

## [1.10.0] - 2026-06-01

## 1.9.1 (2026-05-20) [YANKED]

## v1.9.0 - 2026-05-01

## [2.0.0-rc.1] - 2026-04-01

## [1.8.0]: 2026-03-01

## Not a version

## [UNRELEASED]
'
    got=$(printf '%s\n' "$fixture" | extract_versions | tr '\n' ' ')
    want='1.10.0 1.9.1 1.9.0 2.0.0-rc.1 1.8.0 '
    [ "$got" = "$want" ] || { echo "heading parser produced '$got' (expected '$want')"; return 1; }
    got=$(printf '## [Unreleased]\n## [unreleased] - soon\n## 1.2\n## 1.2.3.4\n' | extract_versions)
    [ -z "$got" ] || { echo "heading parser accepted a non-release heading: $got"; return 1; }

    got=$(printf '1.9.0\n1.10.0\n1.9.1\n' | newest_version)
    [ "$got" = "1.10.0" ] || { echo "newest_version picked '$got' (expected 1.10.0: numeric component sort)"; return 1; }
    got=$(printf '2.0.0-rc.1\n2.0.0\n' | newest_version)
    [ "$got" = "2.0.0" ] || { echo "newest_version ranked a prerelease above its release: $got"; return 1; }
    got=$(printf '1.0.0-rc.10\n1.0.0-rc.2\n1.0.0-rc.9\n' | newest_version)
    [ "$got" = "1.0.0-rc.10" ] || { echo "newest_version compared numeric prerelease identifiers textually: $got (expected 1.0.0-rc.10)"; return 1; }
    got=$(printf '1.0.0-beta\n1.0.0-alpha.1\n1.0.0-alpha\n1.0.0-1\n' | newest_version)
    [ "$got" = "1.0.0-beta" ] || { echo "newest_version broke SemVer prerelease precedence: $got (expected 1.0.0-beta)"; return 1; }
    got=$(printf '1.0.0-alpha\n1.0.0-alpha.1\n' | newest_version)
    [ "$got" = "1.0.0-alpha.1" ] || { echo "newest_version did not rank the longer identifier list higher: $got"; return 1; }
    got=$(printf '1.0.0+build.2\n1.0.0-rc.1+build.9\n' | newest_version)
    [ "$got" = "1.0.0+build.2" ] || { echo "newest_version let build metadata affect precedence: $got"; return 1; }
    got=$(printf '9007199254740993.0.0\n9007199254740992.0.0\n' | newest_version)
    [ "$got" = "9007199254740993.0.0" ] || { echo "newest_version collapsed integers beyond 2^53: $got"; return 1; }
    got=$(printf '1.0.0-rc.9007199254740993\n1.0.0-rc.9007199254740992\n' | newest_version)
    [ "$got" = "1.0.0-rc.9007199254740993" ] || { echo "newest_version collapsed prerelease integers beyond 2^53: $got"; return 1; }

    tags='v1.0.0
1.0.1
release-1.0.2'
    t=$(tag_for 1.0.0 "$tags" __DEFAULT__) && [ "$t" = "v1.0.0" ] || { echo "tag matcher missed v-prefixed tag"; return 1; }
    t=$(tag_for 1.0.1 "$tags" __DEFAULT__) && [ "$t" = "1.0.1" ] || { echo "tag matcher missed bare tag"; return 1; }
    tag_for 1.0.2 "$tags" __DEFAULT__ >/dev/null && { echo "tag matcher accepted a foreign prefix by default"; return 1; }
    t=$(tag_for 1.0.2 "$tags" release-) && [ "$t" = "release-1.0.2" ] || { echo "tag matcher missed declared prefix"; return 1; }
    tag_for 1.0.0 "$tags" release- >/dev/null && { echo "tag matcher fell back to v-tag despite a declared prefix"; return 1; }
    tag_for 1.0.0 "$tags" "" >/dev/null && { echo "empty declared prefix matched a v-tag"; return 1; }
    tag_for 9.9.9 "$tags" __DEFAULT__ >/dev/null && { echo "tag matcher matched a tag that does not exist"; return 1; }

    tmp=$(mktemp -d "${TMPDIR:-/tmp}/changelog-tags-selftest.XXXXXX") || { echo "mktemp failed"; return 1; }
    printf '{\n  "name": "x",\n  "version": "0.1.3",\n  "dependencies": { "left-pad": "1.3.0" }\n}\n' > "$tmp/package.json"
    got=$(manifest_version_package_json "$tmp/package.json")
    [ "$got" = "0.1.3" ] || { rm -rf "$tmp"; echo "package.json reader returned '$got'"; return 1; }
    printf '{"name":"x","version":"0.2.0","dependencies":{"left-pad":"1.3.0"}}' > "$tmp/package.json"
    got=$(manifest_version_package_json "$tmp/package.json")
    [ "$got" = "0.2.0" ] || { rm -rf "$tmp"; echo "package.json reader missed a compact one-line manifest: '$got'"; return 1; }
    printf '{\n  "releaseConfig": { "version": "9.9.9", "tags": ["v:1"] },\n  "scripts": { "x": "echo \\"version\\": {" },\n  "version": "0.4.0"\n}\n' > "$tmp/package.json"
    got=$(manifest_version_package_json "$tmp/package.json")
    [ "$got" = "0.4.0" ] || { rm -rf "$tmp"; echo "package.json reader took a nested version instead of the root one: '$got'"; return 1; }
    printf '{\n  "name": "x",\n  "private": true\n}\n' > "$tmp/package.json"
    got=$(manifest_version_package_json "$tmp/package.json")
    [ -z "$got" ] || { rm -rf "$tmp"; echo "package.json reader invented a version for a versionless manifest: '$got'"; return 1; }
    printf '{\n  "name": "x",\n  "version": "0.3.0"\n}\n' > "$tmp/package.json"
    printf '[package]\nname = "x"\nversion = "0.2.9"\n' > "$tmp/Cargo.toml"
    got=$(root_manifest_versions "$tmp" | tr '\n' ' ')
    [ "$got" = "package.json 0.3.0 Cargo.toml 0.2.9 " ] || { rm -rf "$tmp"; echo "root_manifest_versions stopped at the first manifest: '$got'"; return 1; }
    rm -f "$tmp/Cargo.toml"
    printf '[workspace]\nmembers = ["a"]\n\n[workspace.package]\nversion = "2.3.4"\n\n[workspace.dependencies]\nserde = { version = "1.0" }\n' > "$tmp/Cargo.toml"
    got=$(manifest_version_cargo_toml "$tmp/Cargo.toml")
    [ "$got" = "2.3.4" ] || { rm -rf "$tmp"; echo "Cargo.toml reader returned '$got' (expected 2.3.4 from [workspace.package])"; return 1; }
    printf '[package]\nname = "m"\nversion.workspace = true\n\n[dependencies]\nfoo = { version = "9.9.9" }\n' > "$tmp/Cargo.toml"
    got=$(manifest_version_cargo_toml "$tmp/Cargo.toml")
    [ -z "$got" ] || { rm -rf "$tmp"; echo "Cargo.toml reader took a dependency version: '$got'"; return 1; }
    printf '[package]\nname = "m"\nversion = '"'"'0.9.0'"'"'\n' > "$tmp/Cargo.toml"
    got=$(manifest_version_cargo_toml "$tmp/Cargo.toml")
    [ "$got" = "0.9.0" ] || { rm -rf "$tmp"; echo "Cargo.toml reader rejected a TOML literal string: '$got'"; return 1; }
    printf '[package] # root crate\nname = "m"\nversion = "0.9.1"\n' > "$tmp/Cargo.toml"
    got=$(manifest_version_cargo_toml "$tmp/Cargo.toml")
    [ "$got" = "0.9.1" ] || { rm -rf "$tmp"; echo "Cargo.toml reader lost a section header with a trailing comment: '$got'"; return 1; }
    printf '[project]   # metadata\nname = "p"\nversion = "4.5.7"\n' > "$tmp/pyproject.toml"
    got=$(manifest_version_pyproject "$tmp/pyproject.toml")
    [ "$got" = "4.5.7" ] || { rm -rf "$tmp"; echo "pyproject.toml reader lost a section header with a trailing comment: '$got'"; return 1; }
    printf 'package.name = "m"\npackage.version = "0.9.2"\n\n[dependencies]\nfoo = { version = "9.9.9" }\n' > "$tmp/Cargo.toml"
    got=$(manifest_version_cargo_toml "$tmp/Cargo.toml")
    [ "$got" = "0.9.2" ] || { rm -rf "$tmp"; echo "Cargo.toml reader missed the dotted key package.version: '$got'"; return 1; }
    printf '[workspace]\nmembers = ["a"]\npackage.version = "0.9.3"\n' > "$tmp/Cargo.toml"
    got=$(manifest_version_cargo_toml "$tmp/Cargo.toml")
    [ "$got" = "0.9.3" ] || { rm -rf "$tmp"; echo "Cargo.toml reader missed package.version under [workspace]: '$got'"; return 1; }
    printf 'project.name = "p"\nproject.version = "4.5.8"\n' > "$tmp/pyproject.toml"
    got=$(manifest_version_pyproject "$tmp/pyproject.toml")
    [ "$got" = "4.5.8" ] || { rm -rf "$tmp"; echo "pyproject.toml reader missed the dotted key project.version: '$got'"; return 1; }
    printf '[tool]\npoetry.name = "p"\npoetry.version = "4.5.9"\n' > "$tmp/pyproject.toml"
    got=$(manifest_version_pyproject "$tmp/pyproject.toml")
    [ "$got" = "4.5.9" ] || { rm -rf "$tmp"; echo "pyproject.toml reader missed poetry.version under [tool]: '$got'"; return 1; }
    printf '[build-system]\nrequires = ["hatchling"]\n\n[project]\nname = "p"\nversion = '"'"'4.5.6'"'"'\n' > "$tmp/pyproject.toml"
    got=$(manifest_version_pyproject "$tmp/pyproject.toml")
    [ "$got" = "4.5.6" ] || { rm -rf "$tmp"; echo "pyproject.toml reader returned '$got'"; return 1; }
    printf '[project]\nname = "p"\ndynamic = ["version"]\n' > "$tmp/pyproject.toml"
    got=$(manifest_version_pyproject "$tmp/pyproject.toml")
    [ -z "$got" ] || { rm -rf "$tmp"; echo "pyproject.toml reader invented a version for a dynamic project: '$got'"; return 1; }
    rm -rf "$tmp"
    return 0
}

if ! self_test_msg=$(self_test); then
    echo "FAIL $CHECK_NAME self-test failed (detector rot, refusing to report): $self_test_msg"
    exit 1
fi

# ---------------------------------------------------------------------------
# Configuration — .standards.yml `release:` block
# ---------------------------------------------------------------------------
# read_release_key <key> → the value, `__EMPTY__` when the key is present with
# no value, or nothing when the key is absent
read_release_key() {
    [ -f "$PROJECT_ROOT/.standards.yml" ] || return 0
    awk -v key="$1" '
        /^release:/ { inblk = 1; next }
        inblk && /^[^[:space:]#]/ { exit }
        inblk && $0 ~ "^[[:space:]]+" key ":" {
            sub("^[[:space:]]*" key ":[[:space:]]*", "")
            sub(/[[:space:]]+#.*$/, "")
            sub(/[[:space:]]+$/, "")
            gsub(/^["'"'"']|["'"'"']$/, "")
            if ($0 == "" || $0 == "~" || $0 == "null") print "__EMPTY__"; else print
            exit
        }' "$PROJECT_ROOT/.standards.yml" 2>/dev/null
}

DECLARED=$(read_release_key changelog)
TAG_PREFIX=$(read_release_key tag_prefix)
case "$TAG_PREFIX" in
    "") TAG_PREFIX="__DEFAULT__" ;;          # not declared: accept v<ver> and <ver>
    __EMPTY__) TAG_PREFIX="" ;;              # declared empty: bare <ver> only
esac
if [ "$TAG_PREFIX" = "__DEFAULT__" ]; then
    PREFIX_LABEL="v<version> or <version>"
else
    PREFIX_LABEL="${TAG_PREFIX}<version>"
fi

if [ "$DECLARED" = "__EMPTY__" ]; then
    echo "FAIL $CHECK_NAME .standards.yml declares release.changelog with no value — set a path or remove the key (failing closed)"
    exit 1
fi

CHANGELOG=""
CHANGELOG_LABEL=""
if [ -n "$DECLARED" ]; then
    CHANGELOG_LABEL="$DECLARED"
    if [ ! -f "$PROJECT_ROOT/$DECLARED" ]; then
        echo "FAIL $CHECK_NAME .standards.yml declares release.changelog: $DECLARED but the file does not exist (failing closed)"
        exit 1
    fi
    CHANGELOG="$PROJECT_ROOT/$DECLARED"
else
    for candidate in $DEFAULT_LOCATIONS; do
        if [ -f "$PROJECT_ROOT/$candidate" ]; then
            CHANGELOG="$PROJECT_ROOT/$candidate"
            CHANGELOG_LABEL="$candidate"
            break
        fi
    done
fi

if [ -z "$CHANGELOG" ]; then
    echo "PASS $CHECK_NAME No CHANGELOG (none declared in .standards.yml, no CHANGELOG.md/CHANGES.md/HISTORY.md at the root) — nothing to reconcile with tags"
    exit 0
fi

if [ ! -r "$CHANGELOG" ] || [ ! -s "$CHANGELOG" ]; then
    echo "FAIL $CHECK_NAME $CHANGELOG_LABEL is empty or unreadable — cannot pass (failing closed)"
    exit 1
fi

# ---------------------------------------------------------------------------
# Tags
# ---------------------------------------------------------------------------
if ! git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    echo "WARN $CHECK_NAME $CHANGELOG_LABEL found but $PROJECT_ROOT is not a git repository — cannot read tags, not verified"
    exit 2
fi

TAGS=$(git -C "$PROJECT_ROOT" tag -l 2>/dev/null)
TAG_COUNT=0
if [ -n "$TAGS" ]; then
    TAG_COUNT=$(printf '%s\n' "$TAGS" | grep -c . || true)
fi

IS_SHALLOW=false
shallow_answer=$(git -C "$PROJECT_ROOT" rev-parse --is-shallow-repository 2>/dev/null || true)
if [ "$shallow_answer" = "true" ]; then
    IS_SHALLOW=true
elif [ -z "$shallow_answer" ] || [ "$shallow_answer" = "--is-shallow-repository" ]; then
    # git < 2.15 echoes the unknown flag back; fall back to the marker file.
    git_dir=$(git -C "$PROJECT_ROOT" rev-parse --git-dir 2>/dev/null || true)
    [ -n "$git_dir" ] && [ -f "$git_dir/shallow" ] && IS_SHALLOW=true
fi

# ---------------------------------------------------------------------------
# Reconcile headings with tags
# ---------------------------------------------------------------------------
VERSIONS=$(extract_versions < "$CHANGELOG")
VERSION_COUNT=0
if [ -n "$VERSIONS" ]; then
    VERSION_COUNT=$(printf '%s\n' "$VERSIONS" | grep -c . || true)
fi

if [ "$VERSION_COUNT" -eq 0 ]; then
    if [ "$TAG_COUNT" -gt 0 ]; then
        echo "WARN $CHECK_NAME $CHANGELOG_LABEL has no release heading (## [x.y.z]) but the repository has $TAG_COUNT tag(s) — releases are tagged but not recorded (proc-02 §5)"
        exit 2
    fi
    echo "PASS $CHECK_NAME $CHANGELOG_LABEL lists 0 release headings (Unreleased only) and the repository has no tags — nothing to reconcile yet"
    exit 0
fi

if [ "$TAG_COUNT" -eq 0 ] && [ "$IS_SHALLOW" = true ]; then
    echo "WARN $CHECK_NAME $CHANGELOG_LABEL lists $VERSION_COUNT release heading(s) but this is a shallow clone with no tags fetched — cannot verify; use actions/checkout with fetch-depth: 0 or fetch-tags: true"
    exit 2
fi

MISSING=""
MISSING_COUNT=0
while IFS= read -r version; do
    [ -n "$version" ] || continue
    if ! tag_for "$version" "$TAGS" "$TAG_PREFIX" >/dev/null; then
        MISSING_COUNT=$((MISSING_COUNT + 1))
        if [ "$MISSING_COUNT" -le "$MAX_LISTED" ]; then
            MISSING="${MISSING}${MISSING:+, }$version"
        fi
    fi
done <<EOF
$VERSIONS
EOF

LATEST=$(printf '%s\n' "$VERSIONS" | newest_version)

if [ "$MISSING_COUNT" -gt 0 ]; then
    more=""
    if [ "$MISSING_COUNT" -gt "$MAX_LISTED" ]; then more=" (+$((MISSING_COUNT - MAX_LISTED)) more)"; fi
    # A tag under ANY prefix that ends in the version (`prod-2.0.0`, `v2.0.0`,
    # `2.0.0`) means the release was tagged, just not as declared: misnamed,
    # not in flight. The version is regex-escaped before the suffix match, and
    # a digit or dot directly before it is rejected so `v12.0.0` is not a tag
    # for `2.0.0`.
    latest_ere=$(printf '%s' "$LATEST" | sed 's/[][\.*^$+?(){}|\\]/\\&/g')
    if [ "$MISSING_COUNT" -eq 1 ] && [ "$MISSING" = "$LATEST" ] \
        && ! printf '%s\n' "$TAGS" | grep -Eq -- "(^|[^0-9.])${latest_ere}\$"; then
        # A release in flight: the release PR promotes [Unreleased] to a
        # numbered heading and the tag is cut after the merge (proc-02 §5), so
        # between those two steps exactly the newest heading has no tag at all.
        # That is advisory. A tag that exists under the wrong prefix is not in
        # flight (it is misnamed), and a second untagged heading, or an older
        # one while newer releases are tagged, is the forgotten-tag pattern;
        # both FAIL below.
        if [ "$TAG_PREFIX" = "__DEFAULT__" ]; then want_tag="v$LATEST"; else want_tag="${TAG_PREFIX}${LATEST}"; fi
        echo "WARN $CHECK_NAME release $LATEST in $CHANGELOG_LABEL has no tag yet — every older heading is tagged, so this looks like a release in flight: create $want_tag once it is merged (proc-02 §5); a second untagged heading would fail"
        exit 2
    fi
    if [ "$IS_SHALLOW" = true ]; then
        # A depth-limited clone carries only the tags that point inside the
        # fetched history (e.g. the tip's tag), so an older release's tag may
        # exist beyond the boundary. Unverifiable, not untagged.
        echo "WARN $CHECK_NAME $MISSING_COUNT of $VERSION_COUNT release heading(s) in $CHANGELOG_LABEL have no visible tag ($MISSING$more) but this is a shallow clone — tags outside the fetched history are invisible, cannot verify; use actions/checkout with fetch-depth: 0 or fetch-tags: true"
        exit 2
    fi
    if [ "$TAG_PREFIX" = "__DEFAULT__" ]; then
        expected="v<version> or <version>"
    else
        expected="${TAG_PREFIX}<version>"
        # Name the exact tag for the first miss so the fix is copy-pasteable.
        first="${MISSING%%,*}"
        expected="$expected (e.g. ${TAG_PREFIX}${first})"
    fi
    echo "FAIL $CHECK_NAME $MISSING_COUNT of $VERSION_COUNT release heading(s) in $CHANGELOG_LABEL have no matching tag (expected $expected): $MISSING$more — tag the release or remove the heading (proc-02 §5)"
    exit 1
fi

# ---------------------------------------------------------------------------
# Manifest drift (advisory)
# ---------------------------------------------------------------------------
DRIFT=""
if [ -n "$LATEST" ]; then
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        manifest_file="${line%% *}"
        manifest_version="${line#* }"
        manifest_version="${manifest_version#v}"
        if [ "$manifest_version" != "$LATEST" ]; then
            DRIFT="${DRIFT}${DRIFT:+, }$manifest_file version $manifest_version"
        fi
    done <<EOF
$(root_manifest_versions "$PROJECT_ROOT")
EOF
fi
if [ -n "$DRIFT" ]; then
    echo "WARN $CHECK_NAME all $VERSION_COUNT release heading(s) in $CHANGELOG_LABEL are tagged, but $DRIFT is not the latest release $LATEST — bump the manifest in the release commit (proc-02 §5)"
    exit 2
fi

echo "PASS $CHECK_NAME $VERSION_COUNT release heading(s) in $CHANGELOG_LABEL each have a matching tag ($PREFIX_LABEL)"
exit 0
