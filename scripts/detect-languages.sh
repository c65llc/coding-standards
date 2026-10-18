#!/bin/bash
# Detect project languages by checking for manifest files in the project root
# and in the conventional monorepo sub-roots (#179): apps/*, packages/*,
# crates/*, core, server, web, shells/*. Outputs one language key per line to
# stdout, each at most once, root first.
#
# Usage: ./detect-languages.sh [--root-only|--subroots-only] [--skip <dir>]... [/path/to/project]
#   or:  PROJECT_ROOT=/path/to/project ./detect-languages.sh
#
# Options:
#   --root-only      Inspect only the project root (no sub-root walk).
#   --subroots-only  Inspect only the conventional sub-roots (not the root's
#                    own manifests), so a language both the root and a
#                    sub-root carry is still attributed to the sub-root.
#   --skip <dir>     Do not inspect this root-relative sub-root (repeatable).
#                    The member-aware scripts pass each declared member here
#                    so a member's languages are judged by its own
#                    .standards.yml.
#
# Manifests recognised: pyproject.toml, setup.py, requirements.txt, Pipfile,
# uv.lock (python); Cargo.toml (rust); Gemfile, .ruby-version (ruby, + rails);
# package.json, deno.json (javascript); tsconfig*.json or .ts sources
# (typescript); build.gradle[.kts], pom.xml (jvm, + java/kotlin); Package.swift
# (swift); pubspec.yaml (dart); build.zig (zig); go.mod (go); mix.exs (elixir);
# CMakeLists.txt, .clang-format or C++ sources (*.cpp, *.cc, *.cxx, *.hpp,
# *.hh, *.hxx) at the root or under src/, include/, lib/, Sources/ (cpp,
# lang-14).

set -e

ROOT_ONLY=false
SUBROOTS_ONLY=false
SKIP_DIRS=""
PROJECT_ROOT_ARG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --root-only)
            ROOT_ONLY=true
            shift
            ;;
        --subroots-only)
            SUBROOTS_ONLY=true
            shift
            ;;
        --skip)
            if [ $# -lt 2 ] || [ -z "$2" ]; then
                echo "detect-languages: --skip requires a directory" >&2
                exit 2
            fi
            SKIP_DIRS="$SKIP_DIRS $2"
            shift 2
            ;;
        --skip=*)
            SKIP_DIRS="$SKIP_DIRS ${1#--skip=}"
            shift
            ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "detect-languages: unknown option: $1" >&2
            exit 2
            ;;
        *)
            PROJECT_ROOT_ARG="$1"
            shift
            ;;
    esac
done

PROJECT_ROOT="${PROJECT_ROOT_ARG:-${PROJECT_ROOT:-}}"
if [ -z "$PROJECT_ROOT" ]; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# Sub-roots inspected in addition to the project root. Globs expand against
# the project root; a pattern with no match is dropped.
WALK_PATTERNS="apps/* packages/* crates/* core server web shells/*"

# detect_in_dir <dir>: print the language keys whose manifests live in <dir>.
detect_in_dir() {
    local dir="$1" f

    # python
    for f in pyproject.toml setup.py requirements.txt Pipfile uv.lock; do
        if [ -f "$dir/$f" ]; then
            echo "python"
            break
        fi
    done

    # rust
    if [ -f "$dir/Cargo.toml" ]; then
        echo "rust"
    fi

    # ruby
    for f in Gemfile .ruby-version; do
        if [ -f "$dir/$f" ]; then
            echo "ruby"
            break
        fi
    done

    # rails (sub-detection within ruby projects)
    if [ -f "$dir/config/routes.rb" ] || { [ -f "$dir/Gemfile" ] && grep -q "rails" "$dir/Gemfile" 2>/dev/null; }; then
        echo "rails"
    fi

    # javascript (covers JS and TS)
    for f in package.json deno.json; do
        if [ -f "$dir/$f" ]; then
            echo "javascript"
            break
        fi
    done

    # typescript (sub-detection: TS-specific tooling within JS/TS projects).
    # Any tsconfig*.json counts (tsconfig.json, tsconfig.app.json,
    # tsconfig.base.json, ...).
    local has_ts=false
    for f in "$dir"/tsconfig*.json; do
        if [ -f "$f" ]; then
            has_ts=true
            break
        fi
    done
    if [ "$has_ts" = true ]; then
        echo "typescript"
    elif find "$dir/src" "$dir/app" "$dir/lib" -maxdepth 2 \( -name "*.ts" -o -name "*.tsx" \) 2>/dev/null | head -1 | grep -q .; then
        echo "typescript"
    fi

    # jvm (Java, Kotlin, Scala, etc.)
    for f in build.gradle build.gradle.kts pom.xml; do
        if [ -f "$dir/$f" ]; then
            echo "jvm"
            break
        fi
    done

    # java / kotlin (sub-detection within JVM projects)
    if [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ] || [ -f "$dir/pom.xml" ]; then
        if find "$dir/src" -maxdepth 3 -name "*.java" 2>/dev/null | head -1 | grep -q .; then
            echo "java"
        fi
        if find "$dir/src" -maxdepth 3 \( -name "*.kt" -o -name "*.kts" \) 2>/dev/null | head -1 | grep -q .; then
            echo "kotlin"
        fi
    fi

    # swift
    if [ -f "$dir/Package.swift" ]; then
        echo "swift"
    fi

    # dart
    if [ -f "$dir/pubspec.yaml" ]; then
        echo "dart"
    fi

    # zig
    if [ -f "$dir/build.zig" ]; then
        echo "zig"
    fi

    # go
    if [ -f "$dir/go.mod" ]; then
        echo "go"
    fi

    # elixir
    if [ -f "$dir/mix.exs" ]; then
        echo "elixir"
    fi

    # cpp (lang-14): a CMake project, a clang-format config, or C++ sources at
    # the root or under the conventional source roots. A Swift package or
    # Android app that carries a C++ core under Sources/ or src/ is detected
    # here as well, so the C ABI rules reach the project that owns the engine.
    if [ -f "$dir/CMakeLists.txt" ] || [ -f "$dir/.clang-format" ] || [ -f "$dir/_clang-format" ]; then
        echo "cpp"
    elif find "$dir" -maxdepth 1 \( -name "*.cpp" -o -name "*.cc" -o -name "*.cxx" -o -name "*.hpp" -o -name "*.hh" -o -name "*.hxx" \) 2>/dev/null | head -1 | grep -q .; then
        echo "cpp"
    elif find "$dir/src" "$dir/include" "$dir/lib" "$dir/Sources" -maxdepth 3 \( -name "*.cpp" -o -name "*.cc" -o -name "*.cxx" -o -name "*.hpp" -o -name "*.hh" -o -name "*.hxx" \) 2>/dev/null | head -1 | grep -q .; then
        echo "cpp"
    fi
}

# skipped <root-relative dir>: true when it is, or lies under, a --skip entry.
skipped() {
    local rel="$1" s
    for s in $SKIP_DIRS; do
        s="${s#./}"
        s="${s%/}"
        [ -z "$s" ] && continue
        case "$rel" in
            "$s"|"$s"/*) return 0 ;;
        esac
    done
    return 1
}

if [ "$ROOT_ONLY" = true ] && [ "$SUBROOTS_ONLY" = true ]; then
    echo "detect-languages: --root-only and --subroots-only are mutually exclusive" >&2
    exit 2
fi

{
    [ "$SUBROOTS_ONLY" = true ] || detect_in_dir "$PROJECT_ROOT"
    if [ "$ROOT_ONLY" = false ]; then
        for pattern in $WALK_PATTERNS; do
            for dir in "$PROJECT_ROOT"/$pattern; do
                [ -d "$dir" ] || continue
                rel="${dir#"$PROJECT_ROOT/"}"
                case "$rel" in
                    .*|*/.*) continue ;;   # hidden directories are never project roots
                esac
                # A symlinked sub-root (or a symlinked parent such as apps/)
                # could point outside the checkout; setup, sync and diff build
                # agent and tool configuration from this detection, so it must
                # never depend on files that are not the repository's own.
                [ -L "$dir" ] && continue
                case "$rel" in
                    */*) [ -L "$PROJECT_ROOT/${rel%%/*}" ] && continue ;;
                esac
                skipped "$rel" && continue
                detect_in_dir "$dir"
            done
        done
    fi
} | awk '!seen[$0]++'
