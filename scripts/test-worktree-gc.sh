#!/bin/bash
# Functional tests for worktree hygiene tooling (proc-04 § Worktree Hygiene, #190):
# scripts/worktree-gc.sh, scripts/lib/worktrees.sh, the doctor.sh Worktrees
# check, the pre-commit worktree guard template, and the worktree-root
# exclusions in members.sh and lint-files.sh.
#
# Each test builds a temp repository with a bare "origin" and a set of linked
# worktrees in known states, runs the tool, and asserts outcomes.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GC="$REPO_ROOT/scripts/worktree-gc.sh"
DOCTOR="$REPO_ROOT/scripts/doctor.sh"
GUARD="$REPO_ROOT/templates/pre-commit-worktree-guard.example"
LIB="$REPO_ROOT/scripts/lib/worktrees.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS=0; FAIL=0

TMP_BASE="$(mktemp -d "${TMPDIR:-/tmp}/test-worktree-gc.XXXXXX")"
# Resolve symlinks (macOS /tmp -> /private/tmp) so paths compare equal to git's.
TMP_BASE="$(cd "$TMP_BASE" && pwd -P)"
trap 'rm -rf "$TMP_BASE"' EXIT

pass() { echo -e "${GREEN}✓${NC}"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}✗${NC}"; echo "  Error: $1"; FAIL=$((FAIL + 1)); }

G() { git -c user.email="t@t.local" -c user.name="T" -c commit.gpgsign=false -c init.defaultBranch=main "$@"; }

# make_repo <name> → prints the clone path. A bare origin lives next to it so
# "merged" and "gone" branches can be modelled against origin/main.
make_repo() {
    local name="$1"
    local bare="$TMP_BASE/$name.git" dir="$TMP_BASE/$name"
    G init -q --bare "$bare"
    G clone -q "$bare" "$dir" 2>/dev/null
    ( cd "$dir" \
        && G checkout -q -b main 2>/dev/null \
        && printf '.claude/worktrees/\n' > .gitignore \
        && printf 'version: 1\nlanguages: []\nagents: []\nrole: service\n' > .standards.yml \
        && G add .gitignore .standards.yml \
        && G commit -q -m "chore: init" \
        && G push -q -u origin main 2>/dev/null )
    echo "$dir"
}

# add_wt <repo> <path-rel> <branch> [file] → linked worktree with one commit.
add_wt() {
    local repo="$1" rel="$2" branch="$3"
    local file="${4:-$branch.txt}"
    ( cd "$repo" && G worktree add -q "$rel" -b "$branch" 2>/dev/null \
        && cd "$rel" && echo "x" > "$(basename "$file")" && G add . && G commit -q -m "feat: $branch" )
}

# backdate <worktree path> <days> → make every activity marker <days> old.
backdate() {
    local wt="$1" days="$2" stamp gitdir
    stamp=$(date -v-"${days}"d +%Y%m%d%H%M 2>/dev/null || date -d "-${days} days" +%Y%m%d%H%M)
    gitdir=$(cd "$wt" && git rev-parse --git-dir)
    case "$gitdir" in /*) ;; *) gitdir="$wt/$gitdir" ;; esac
    ( cd "$wt" && GIT_COMMITTER_DATE="$(date -v-"${days}"d 2>/dev/null || date -d "-${days} days")" \
        G commit -q --amend --no-edit --date="$(date -v-"${days}"d 2>/dev/null || date -d "-${days} days")" )
    touch -t "$stamp" "$wt" "$gitdir/HEAD" "$gitdir/index" "$gitdir/logs/HEAD" 2>/dev/null
}

# Fixture: a repository with one worktree in every state the collector handles.
build_fixture() {
    local repo="$1"
    # merged: commit landed on origin/main, remote branch still there
    add_wt "$repo" .claude/worktrees/merged feat/merged
    ( cd "$repo" && G push -q -u origin feat/merged 2>/dev/null && G merge -q --ff-only feat/merged && G push -q origin main 2>/dev/null )
    # gone: pushed, then the remote branch was deleted (squash-merged elsewhere)
    add_wt "$repo" .claude/worktrees/gone feat/gone
    ( cd "$repo/.claude/worktrees/gone" && G push -q -u origin feat/gone 2>/dev/null && G push -q origin --delete feat/gone 2>/dev/null )
    # stale: unmerged, idle for 40 days
    add_wt "$repo" .claude/worktrees/stale feat/stale
    backdate "$repo/.claude/worktrees/stale" 40
    # active: unmerged, fresh
    add_wt "$repo" .claude/worktrees/active feat/active
    # dirty-merged: merged, with an uncommitted file
    add_wt "$repo" .claude/worktrees/dirty feat/dirty
    ( cd "$repo" && G push -q -u origin feat/dirty 2>/dev/null && G merge -q --ff-only feat/dirty && G push -q origin main 2>/dev/null )
    echo "wip" > "$repo/.claude/worktrees/dirty/uncommitted.txt"
    # locked: merged but locked — never touched
    add_wt "$repo" .claude/worktrees/locked feat/locked
    ( cd "$repo" && G push -q -u origin feat/locked 2>/dev/null && G merge -q --ff-only feat/locked && G push -q origin main 2>/dev/null && G worktree lock .claude/worktrees/locked )
    # prunable: directory deleted, registration left behind
    add_wt "$repo" .claude/worktrees/prunable feat/prunable
    rm -rf "$repo/.claude/worktrees/prunable"
    # nested: created from inside the active worktree
    ( cd "$repo/.claude/worktrees/active" && G worktree add -q .claude/worktrees/nested -b feat/nested 2>/dev/null )
    # outside: under another agent's root
    add_wt "$repo" .Codex/worktrees/outside feat/outside
}

wt_paths() { ( cd "$1" && git worktree list --porcelain | sed -n 's/^worktree //p' ); }

echo -e "${BLUE}Testing worktree hygiene tooling (worktree-gc.sh, doctor Worktrees, pre-commit guard)${NC}"
echo ""

# --- Library ---------------------------------------------------------------

echo -n "Test 1: worktree-gc.sh exists and is executable... "
if [ -x "$GC" ]; then pass; else fail "$GC not executable"; fi

echo -n "Test 2: worktree_dir_normalize accepts project-relative roots and rejects absolute, home and .. paths... "
out=$(bash -c "source '$LIB'
    a=\$(worktree_dir_normalize './tools/wt/')      || a=REJ
    b=\$(worktree_dir_normalize '\"agents//worktrees\"  # c') || b=REJ
    c=\$(worktree_dir_normalize '/abs/path')          || c=REJ
    d=\$(worktree_dir_normalize '../escape')          || d=REJ
    e=\$(worktree_dir_normalize 'ok/../escape')       || e=REJ
    f=\$(worktree_dir_normalize '~/wt')               || f=REJ
    g=\$(worktree_dir_normalize '')                   || g=REJ
    h=\$(worktree_dir_normalize '.')                  || h=REJ
    printf '%s|%s|%s|%s|%s|%s|%s|%s' \"\$a\" \"\$b\" \"\$c\" \"\$d\" \"\$e\" \"\$f\" \"\$g\" \"\$h\"")
if [ "$out" = "tools/wt|agents/worktrees|REJ|REJ|REJ|REJ|REJ|REJ" ]; then pass; else fail "got: $out"; fi

echo -n "Test 3: worktree_root_dir reads worktree_dir: from .standards.yml, defaults to .claude/worktrees, flags an invalid value... "
d="$TMP_BASE/rootdir"; mkdir -p "$d/a" "$d/b" "$d/c"
printf 'version: 1\nworktree_dir: tools/wt\n' > "$d/a/.standards.yml"
printf 'version: 1\n' > "$d/b/.standards.yml"
printf 'version: 1\nworktree_dir: /abs\n' > "$d/c/.standards.yml"
out=$(bash -c "source '$LIB'
    a=\$(worktree_root_dir '$d/a'); b=\$(worktree_root_dir '$d/b'); c=\$(worktree_root_dir '$d/c'); inv=\$(worktree_dir_problem '$d/c')
    printf '%s|%s|%s|%s' \"\$a\" \"\$b\" \"\$c\" \"\$inv\"")
if [ "$out" = "tools/wt|.claude/worktrees|.claude/worktrees|/abs" ]; then pass; else fail "got: $out"; fi

echo -n "Test 4: worktree_list reports main first, then branch and state per worktree... "
repo=$(make_repo "list")
add_wt "$repo" .claude/worktrees/one feat/one
( cd "$repo" && G worktree lock .claude/worktrees/one )
out=$(bash -c "source '$LIB'; worktree_list '$repo'")
first=$(printf '%s\n' "$out" | head -1 | cut -f1)
one=$(printf '%s\n' "$out" | grep "/one" | cut -f2,3)
if [ "$first" = "$repo" ] && [ "$one" = "$(printf 'feat/one\tlocked')" ]; then pass; else fail "got: $out"; fi

echo -n "Test 5: worktree_age_days measures idle days from commit/checkout activity... "
repo=$(make_repo "age")
add_wt "$repo" .claude/worktrees/old feat/old
add_wt "$repo" .claude/worktrees/new feat/new
backdate "$repo/.claude/worktrees/old" 30
out=$(bash -c "source '$LIB'; printf '%s|%s' \"\$(worktree_age_days '$repo/.claude/worktrees/old')\" \"\$(worktree_age_days '$repo/.claude/worktrees/new')\"")
old_days=${out%%|*}; new_days=${out##*|}
if [ "$old_days" -ge 29 ] && [ "$old_days" -le 31 ] && [ "$new_days" -eq 0 ]; then pass; else fail "got old=$old_days new=$new_days"; fi

echo -n "Test 6: worktree_nested_in finds a worktree created inside another linked worktree... "
out=$(bash -c "source '$LIB'
    paths=\$(printf '%s\n%s\n%s' /r/.claude/worktrees/a /r/.claude/worktrees/a/.claude/worktrees/b /r/.claude/worktrees/c)
    n=\$(worktree_nested_in /r/.claude/worktrees/a/.claude/worktrees/b \"\$paths\") || n=NONE
    m=\$(worktree_nested_in /r/.claude/worktrees/c \"\$paths\") || m=NONE
    printf '%s|%s' \"\$n\" \"\$m\"")
if [ "$out" = "/r/.claude/worktrees/a|NONE" ]; then pass; else fail "got: $out"; fi

# --- worktree-gc.sh --------------------------------------------------------

echo -n "Test 7: --help exits 0 and an unknown option exits 2 without touching anything... "
repo=$(make_repo "usage")
add_wt "$repo" .claude/worktrees/keep feat/keep
"$GC" --help >/dev/null 2>&1; rc_help=$?
( cd "$repo" && "$GC" --bogus >/dev/null 2>&1 ); rc_bad=$?
if [ "$rc_help" -eq 0 ] && [ "$rc_bad" -eq 2 ] && [ -d "$repo/.claude/worktrees/keep" ]; then pass; else fail "help=$rc_help bad=$rc_bad"; fi

echo -n "Test 8: --dry-run names the merged, gone, stale and prunable worktrees and removes nothing... "
repo=$(make_repo "dry")
build_fixture "$repo"
before=$(wt_paths "$repo" | wc -l | tr -d ' ')
out=$(cd "$repo" && "$GC" --dry-run --no-fetch 2>&1); rc=$?
after=$(wt_paths "$repo" | wc -l | tr -d ' ')
errs=""
[ "$rc" -eq 0 ]                                                  || errs="$errs rc=$rc"
[ "$before" = "$after" ]                                         || errs="$errs count-changed($before->$after)"
[ -d "$repo/.claude/worktrees/merged" ]                          || errs="$errs merged-removed"
echo "$out" | grep -q 'Would remove.*worktrees/merged.*merged'   || errs="$errs merged-not-listed"
echo "$out" | grep -q 'Would remove.*worktrees/gone.*gone'       || errs="$errs gone-not-listed"
echo "$out" | grep -q 'Would remove.*worktrees/stale.*idle'      || errs="$errs stale-not-listed"
echo "$out" | grep -q 'Would prune.*worktrees/prunable'          || errs="$errs prunable-not-listed"
echo "$out" | grep -q 'keep.*worktrees/active'                   || errs="$errs active-not-kept"
echo "$out" | grep -qi 'dry run'                                 || errs="$errs no-dry-run-banner"
if [ -z "$errs" ]; then pass; else fail "$errs:
$out"; fi

echo -n "Test 9: a real run removes merged, gone, stale, dirty and prunable worktrees and keeps active, locked and nested ones... "
repo=$(make_repo "real")
build_fixture "$repo"
out=$(cd "$repo" && "$GC" --no-fetch 2>&1); rc=$?
errs=""
[ "$rc" -eq 0 ]                                       || errs="$errs rc=$rc"
[ ! -d "$repo/.claude/worktrees/merged" ]             || errs="$errs merged-kept"
[ ! -d "$repo/.claude/worktrees/gone" ]               || errs="$errs gone-kept"
[ ! -d "$repo/.claude/worktrees/stale" ]              || errs="$errs stale-kept"
[ ! -d "$repo/.claude/worktrees/dirty" ]              || errs="$errs dirty-kept"
[ -d "$repo/.claude/worktrees/active" ]               || errs="$errs active-removed"
[ -d "$repo/.claude/worktrees/locked" ]               || errs="$errs locked-removed"
[ -d "$repo/.claude/worktrees/active/.claude/worktrees/nested" ] || errs="$errs nested-removed"
wt_paths "$repo" | grep -q 'prunable'                 && errs="$errs prunable-still-registered"
echo "$out" | grep -q 'reclaimed'                     || errs="$errs no-size-report"
if [ -z "$errs" ]; then pass; else fail "$errs:
$out"; fi

echo -n "Test 10: merged branches are deleted; the gone and stale branches (commits not in the base) are kept... "
branches=$(cd "$repo" && git branch --format='%(refname:short)' | tr '\n' ' ')
errs=""
case " $branches " in *" feat/merged "*) errs="$errs merged-branch-kept" ;; esac
case " $branches " in *" feat/gone "*)   ;; *) errs="$errs gone-branch-deleted" ;; esac
case " $branches " in *" feat/dirty "*)  errs="$errs dirty-branch-kept" ;; esac
case " $branches " in *" feat/stale "*)  ;; *) errs="$errs stale-branch-deleted" ;; esac
case " $branches " in *" feat/active "*) ;; *) errs="$errs active-branch-deleted" ;; esac
echo "$out" | grep -q 'branch kept.*feat/stale' || errs="$errs stale-branch-not-reported"
echo "$out" | grep -q 'branch kept.*feat/gone.*upstream gone.*branch -D' || errs="$errs gone-branch-not-reported"
if [ -z "$errs" ]; then pass; else fail "$errs: $branches"; fi

echo -n "Test 11: uncommitted changes, nesting and worktrees outside the root are warned about... "
errs=""
echo "$out" | grep -q 'uncommitted.*worktrees/dirty\|worktrees/dirty.*uncommitted' || errs="$errs no-dirty-warning"
echo "$out" | grep -qi 'nested'                                                    || errs="$errs no-nesting-warning"
echo "$out" | grep -q 'outside.*\.claude/worktrees\|\.Codex/worktrees/outside.*outside' || errs="$errs no-outside-note"
if [ -z "$errs" ]; then pass; else fail "$errs:
$out"; fi

echo -n "Test 12: --keep-dirty leaves a dirty worktree in place and says why... "
repo=$(make_repo "keepdirty")
add_wt "$repo" .claude/worktrees/dirty feat/dirty
( cd "$repo" && G push -q -u origin feat/dirty 2>/dev/null && G merge -q --ff-only feat/dirty && G push -q origin main 2>/dev/null )
echo "wip" > "$repo/.claude/worktrees/dirty/uncommitted.txt"
out=$(cd "$repo" && "$GC" --no-fetch --keep-dirty 2>&1)
if [ -d "$repo/.claude/worktrees/dirty" ] && echo "$out" | grep -q 'keep.*worktrees/dirty.*dirty'; then pass; else fail "$out"; fi

echo -n "Test 13: --max-age raises the idle threshold so a stale worktree is kept... "
repo=$(make_repo "maxage")
add_wt "$repo" .claude/worktrees/stale feat/stale
backdate "$repo/.claude/worktrees/stale" 40
out=$(cd "$repo" && "$GC" --no-fetch --max-age 90 2>&1)
if [ -d "$repo/.claude/worktrees/stale" ] && echo "$out" | grep -q 'keep.*worktrees/stale'; then pass; else fail "$out"; fi

echo -n "Test 14: the worktree the collector runs from is never removed (even when merged)... "
repo=$(make_repo "current")
add_wt "$repo" .claude/worktrees/merged feat/merged
( cd "$repo" && G push -q -u origin feat/merged 2>/dev/null && G merge -q --ff-only feat/merged && G push -q origin main 2>/dev/null )
out=$(cd "$repo/.claude/worktrees/merged" && "$GC" --no-fetch 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -d "$repo/.claude/worktrees/merged" ] && echo "$out" | grep -q 'keep.*worktrees/merged.*current'; then pass; else fail "rc=$rc
$out"; fi

echo -n "Test 15: the main checkout is never a candidate and a non-repository exits 1... "
repo=$(make_repo "main")
out=$(cd "$repo" && "$GC" --no-fetch 2>&1); rc=$?
nog="$TMP_BASE/norepo"; mkdir -p "$nog"
( cd "$nog" && "$GC" --no-fetch >/dev/null 2>&1 ); rc2=$?
if [ "$rc" -eq 0 ] && [ -f "$repo/.standards.yml" ] && echo "$out" | grep -q 'No linked worktrees' && [ "$rc2" -eq 1 ]; then pass; else fail "rc=$rc rc2=$rc2
$out"; fi

echo -n "Test 16: worktree_dir: in .standards.yml is honoured and an unregistered directory under the root is reported, not deleted... "
repo=$(make_repo "cfgroot")
printf 'version: 1\nlanguages: []\nagents: []\nrole: service\nworktree_dir: tools/wt\n' > "$repo/.standards.yml"
printf 'tools/wt/\n' > "$repo/.gitignore"
( cd "$repo" && G add -A && G commit -q -m "chore: worktree root" && G push -q origin main 2>/dev/null )
add_wt "$repo" tools/wt/active feat/active
mkdir -p "$repo/tools/wt/orphan" && echo "junk" > "$repo/tools/wt/orphan/file"
out=$(cd "$repo" && "$GC" --no-fetch 2>&1)
errs=""
echo "$out" | grep -q 'worktree root: tools/wt' || errs="$errs root-not-reported"
echo "$out" | grep -q 'orphan.*not a registered worktree\|not a registered worktree.*orphan' || errs="$errs orphan-not-reported"
[ -d "$repo/tools/wt/orphan" ]                  || errs="$errs orphan-deleted"
echo "$out" | grep -q 'outside'                 && errs="$errs active-marked-outside"
if [ -z "$errs" ]; then pass; else fail "$errs:
$out"; fi

echo -n "Test 17: an invalid worktree_dir: is warned about and the default root is used... "
repo=$(make_repo "badroot")
printf 'version: 1\nworktree_dir: /abs/elsewhere\n' > "$repo/.standards.yml"
out=$(cd "$repo" && "$GC" --no-fetch --dry-run 2>&1)
if echo "$out" | grep -q "worktree_dir: '/abs/elsewhere'.*not" && echo "$out" | grep -q 'worktree root: .claude/worktrees'; then pass; else fail "$out"; fi

# --- doctor.sh -------------------------------------------------------------

echo -n "Test 18: doctor Worktrees check passes with a gitignored root and no linked worktrees... "
repo=$(make_repo "doctor-clean")
out=$(cd "$repo" && bash "$DOCTOR" 2>&1) || true
if echo "$out" | grep 'Worktrees' | grep -q 'PASS.*gitignored' && echo "$out" | grep 'Worktrees' | grep -q 'PASS.*No linked worktrees'; then pass; else fail "$(echo "$out" | grep Worktrees)"; fi

echo -n "Test 19: doctor reports count, age and size of linked worktrees and warns on nesting, strays and stale ones... "
repo=$(make_repo "doctor-busy")
build_fixture "$repo"
out=$(cd "$repo" && bash "$DOCTOR" 2>&1) || true
wt_lines=$(echo "$out" | grep 'Worktrees')
errs=""
echo "$wt_lines" | grep -q 'linked worktree(s)'              || errs="$errs no-count"
echo "$wt_lines" | grep -q 'oldest [0-9][0-9]*d'              || errs="$errs no-age"
echo "$wt_lines" | grep -qE '[0-9.]+[KMG] on disk'            || errs="$errs no-size"
echo "$wt_lines" | grep -q 'WARN.*nested'                     || errs="$errs no-nesting-warn"
echo "$wt_lines" | grep -q 'WARN.*outside the worktree root'  || errs="$errs no-outside-warn"
echo "$wt_lines" | grep -q 'idle > 14d'                       || errs="$errs no-stale-warn"
echo "$out" | grep -q 'make worktree-gc'                      || errs="$errs no-gc-fix"
if [ -z "$errs" ]; then pass; else fail "$errs:
$wt_lines"; fi

echo -n "Test 20: doctor warns when the worktree root is not gitignored and when worktree_dir: is invalid... "
repo=$(make_repo "doctor-ignore")
printf 'version: 1\nworktree_dir: ../escape\n' > "$repo/.standards.yml"
: > "$repo/.gitignore"
out=$(cd "$repo" && bash "$DOCTOR" 2>&1) || true
wt_lines=$(echo "$out" | grep 'Worktrees')
errs=""
echo "$wt_lines" | grep -q 'WARN.*not gitignored'          || errs="$errs no-gitignore-warn"
echo "$wt_lines" | grep -q "WARN.*worktree_dir: '../escape'" || errs="$errs no-invalid-warn"
if [ -z "$errs" ]; then pass; else fail "$errs:
$wt_lines"; fi

# --- pre-commit guard -------------------------------------------------------

echo -n "Test 21: the pre-commit guard refuses a commit that stages a path under the worktree root... "
repo=$(make_repo "guard-refuse")
mkdir -p "$repo/.git/hooks" && cp "$GUARD" "$repo/.git/hooks/pre-commit" && chmod +x "$repo/.git/hooks/pre-commit"
mkdir -p "$repo/.claude/worktrees/stray" && echo "x" > "$repo/.claude/worktrees/stray/file.txt"
out=$(cd "$repo" && G add -f .claude/worktrees/stray/file.txt && G commit -q -m "chore: oops" 2>&1); rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q 'worktree' && echo "$out" | grep -q '.claude/worktrees/stray/file.txt'; then pass; else fail "rc=$rc
$out"; fi

echo -n "Test 22: the guard refuses a worktree staged as a gitlink (submodule) and lets ordinary commits through... "
repo=$(make_repo "guard-gitlink")
mkdir -p "$repo/.git/hooks" && cp "$GUARD" "$repo/.git/hooks/pre-commit" && chmod +x "$repo/.git/hooks/pre-commit"
add_wt "$repo" .claude/worktrees/wt feat/wt
# Stage the worktree directory itself as a gitlink, the awayteam #180 failure.
( cd "$repo" && G update-index --add --cacheinfo 160000,"$(git -C .claude/worktrees/wt rev-parse HEAD)",.claude/worktrees/wt )
out=$(cd "$repo" && G commit -q -m "chore: oops" 2>&1); rc=$?
( cd "$repo" && G rm -q --cached .claude/worktrees/wt >/dev/null 2>&1 )
echo "ok" > "$repo/normal.txt"
out2=$(cd "$repo" && G add normal.txt && G commit -q -m "feat: normal" 2>&1); rc2=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q '.claude/worktrees/wt' && [ "$rc2" -eq 0 ]; then pass; else fail "rc=$rc rc2=$rc2
$out
$out2"; fi

echo -n "Test 23: the guard honours worktree_dir: from .standards.yml and the other known agent roots... "
repo=$(make_repo "guard-cfg")
printf 'version: 1\nworktree_dir: "tools/wt"  # custom\n' > "$repo/.standards.yml"
mkdir -p "$repo/.git/hooks" && cp "$GUARD" "$repo/.git/hooks/pre-commit" && chmod +x "$repo/.git/hooks/pre-commit"
mkdir -p "$repo/tools/wt/a" "$repo/.Codex/worktrees/b" && echo x > "$repo/tools/wt/a/f" && echo x > "$repo/.Codex/worktrees/b/f"
out=$(cd "$repo" && G add -f tools/wt/a/f && G commit -q -m "chore: oops" 2>&1); rc=$?
( cd "$repo" && G reset -q )
out2=$(cd "$repo" && G add -f .Codex/worktrees/b/f && G commit -q -m "chore: oops" 2>&1); rc2=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q 'tools/wt/a/f' && [ "$rc2" -ne 0 ] && echo "$out2" | grep -q '.Codex/worktrees/b/f'; then pass; else fail "rc=$rc rc2=$rc2
$out
$out2"; fi

# --- members.sh and lint-files.sh ------------------------------------------

echo -n "Test 24: member auto-discovery never enters the configured (non-hidden) worktree root... "
repo=$(make_repo "members-root")
printf 'version: 1\nlanguages: []\nagents: []\nrole: service\nworktree_dir: wt\n' > "$repo/.standards.yml"
mkdir -p "$repo/wt/agent-1" "$repo/server"
printf 'version: 1\nlanguages:\n  - python\n' > "$repo/wt/agent-1/.standards.yml"
printf 'version: 1\nlanguages:\n  - python\n' > "$repo/server/.standards.yml"
out=$(bash -c "source '$REPO_ROOT/scripts/lib/members.sh'; discover_members '$repo'" | tr '\n' ' ')
if [ "$out" = "server " ]; then pass; else fail "got: $out"; fi

echo -n "Test 25: lint_list_files skips untracked files under the configured (non-hidden) worktree root... "
repo=$(make_repo "lint-root")
printf 'version: 1\nlanguages: []\nagents: []\nrole: service\nworktree_dir: wt\n' > "$repo/.standards.yml"
mkdir -p "$repo/wt/agent-1" "$repo/src"
echo 'print(1)' > "$repo/wt/agent-1/a.py"
echo 'print(2)' > "$repo/src/b.py"
out=$(bash -c "source '$REPO_ROOT/scripts/lib/lint-files.sh'; lint_list_files '$repo'")
if echo "$out" | grep -q 'src/b.py' && ! echo "$out" | grep -q 'wt/agent-1'; then pass; else fail "got: $out"; fi

# --- Safety edges ----------------------------------------------------------

echo -n "Test 26: a merged worktree that encloses another registered worktree is kept (removing it would delete the child)... "
repo=$(make_repo "encloses")
add_wt "$repo" .claude/worktrees/parent feat/parent
( cd "$repo" && G push -q -u origin feat/parent 2>/dev/null && G merge -q --ff-only feat/parent && G push -q origin main 2>/dev/null )
# The child has unmerged work of its own, so it must be kept in any case.
( cd "$repo/.claude/worktrees/parent" && G worktree add -q .claude/worktrees/child -b feat/child 2>/dev/null \
    && cd .claude/worktrees/child && echo "x" > child.txt && G add . && G commit -q -m "feat: child" )
out=$(cd "$repo" && "$GC" --no-fetch 2>&1); rc=$?
branches=$(cd "$repo" && git branch --format='%(refname:short)' | tr '\n' ' ')
errs=""
[ "$rc" -eq 0 ]                                                         || errs="$errs rc=$rc"
[ -d "$repo/.claude/worktrees/parent" ]                                 || errs="$errs parent-removed"
[ -d "$repo/.claude/worktrees/parent/.claude/worktrees/child" ]         || errs="$errs child-removed"
case " $branches " in *" feat/parent "*) ;; *) errs="$errs parent-branch-deleted" ;; esac
echo "$out" | grep -q 'encloses.*worktrees/child'                       || errs="$errs no-encloses-warning"
echo "$out" | grep -q 'keep.*worktrees/parent.*encloses'                || errs="$errs parent-not-reported-kept"
if [ -z "$errs" ]; then pass; else fail "$errs:
$out"; fi

echo -n "Test 27: with an explicit project-root argument the worktree the shell runs from is still never removed... "
repo=$(make_repo "caller")
add_wt "$repo" .claude/worktrees/merged feat/merged
( cd "$repo" && G push -q -u origin feat/merged 2>/dev/null && G merge -q --ff-only feat/merged && G push -q origin main 2>/dev/null )
out=$(cd "$repo/.claude/worktrees/merged" && "$GC" --no-fetch "$repo" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -d "$repo/.claude/worktrees/merged" ] && echo "$out" | grep -q 'keep.*worktrees/merged.*current'; then pass; else fail "rc=$rc
$out"; fi

echo -n "Test 28: a linked worktree outside the main checkout altogether is reported as outside the root by worktree-gc and doctor... "
repo=$(make_repo "external")
( cd "$repo" && G worktree add -q "$TMP_BASE/external-wt" -b feat/external 2>/dev/null )
out=$(cd "$repo" && "$GC" --no-fetch --dry-run 2>&1)
dout=$(cd "$repo" && bash "$DOCTOR" 2>&1) || true
errs=""
echo "$out" | grep -q 'external-wt.*outside \.claude/worktrees'                  || errs="$errs gc-no-outside-note"
echo "$dout" | grep 'Worktrees' | grep -q 'WARN.*outside the worktree root.*external-wt' || errs="$errs doctor-no-outside-warn"
if [ -z "$errs" ]; then pass; else fail "$errs:
$out
$(echo "$dout" | grep Worktrees)"; fi

echo -n "Test 29: the guard treats a configured root containing spaces as one root and still refuses the known agent roots... "
repo=$(make_repo "guard-spaces")
printf 'version: 1\nworktree_dir: "agent worktrees"\n' > "$repo/.standards.yml"
mkdir -p "$repo/.git/hooks" && cp "$GUARD" "$repo/.git/hooks/pre-commit" && chmod +x "$repo/.git/hooks/pre-commit"
mkdir -p "$repo/agent worktrees/a" "$repo/.claude/worktrees/b" "$repo/agent" && echo x > "$repo/agent worktrees/a/f" && echo x > "$repo/.claude/worktrees/b/f" && echo x > "$repo/agent/ok.txt"
out=$(cd "$repo" && G add -f "agent worktrees/a/f" && G commit -q -m "chore: oops" 2>&1); rc=$?
( cd "$repo" && G reset -q )
out2=$(cd "$repo" && G add -f .claude/worktrees/b/f && G commit -q -m "chore: oops" 2>&1); rc2=$?
( cd "$repo" && G reset -q )
out3=$(cd "$repo" && G add agent/ok.txt && G commit -q -m "feat: fine" 2>&1); rc3=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q 'agent worktrees/a/f' && [ "$rc2" -ne 0 ] && echo "$out2" | grep -q '.claude/worktrees/b/f' && [ "$rc3" -eq 0 ]; then pass; else fail "rc=$rc rc2=$rc2 rc3=$rc3
$out
$out2
$out3"; fi

echo ""
if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}$FAIL failures${NC}"
    exit 1
fi
echo -e "${GREEN}All $PASS tests passed!${NC}"
