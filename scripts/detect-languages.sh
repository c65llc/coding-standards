#!/bin/bash
# Detect project languages by checking for manifest files in the project root.
# Outputs one language key per line to stdout.
#
# Usage: PROJECT_ROOT=/path/to/project ./detect-languages.sh
#   or:  ./detect-languages.sh /path/to/project

set -e

PROJECT_ROOT="${1:-${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"

# python
for f in pyproject.toml setup.py requirements.txt Pipfile uv.lock; do
    if [ -f "$PROJECT_ROOT/$f" ]; then
        echo "python"
        break
    fi
done

# rust
if [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
    echo "rust"
fi

# ruby
for f in Gemfile .ruby-version; do
    if [ -f "$PROJECT_ROOT/$f" ]; then
        echo "ruby"
        break
    fi
done

# rails (sub-detection within ruby projects)
if [ -f "$PROJECT_ROOT/config/routes.rb" ] || ([ -f "$PROJECT_ROOT/Gemfile" ] && grep -q "rails" "$PROJECT_ROOT/Gemfile" 2>/dev/null); then
    echo "rails"
fi

# javascript (covers JS and TS)
for f in package.json deno.json; do
    if [ -f "$PROJECT_ROOT/$f" ]; then
        echo "javascript"
        break
    fi
done

# typescript (sub-detection: TS-specific tooling within JS/TS projects)
if [ -f "$PROJECT_ROOT/tsconfig.json" ] || [ -f "$PROJECT_ROOT/tsconfig.app.json" ]; then
    echo "typescript"
elif find "$PROJECT_ROOT/src" "$PROJECT_ROOT/app" "$PROJECT_ROOT/lib" -maxdepth 2 -name "*.ts" -o -name "*.tsx" 2>/dev/null | head -1 | grep -q .; then
    echo "typescript"
fi

# jvm (Java, Kotlin, Scala, etc.)
for f in build.gradle build.gradle.kts pom.xml; do
    if [ -f "$PROJECT_ROOT/$f" ]; then
        echo "jvm"
        break
    fi
done

# java (sub-detection within JVM projects)
if [ -f "$PROJECT_ROOT/build.gradle" ] || [ -f "$PROJECT_ROOT/build.gradle.kts" ] || [ -f "$PROJECT_ROOT/pom.xml" ]; then
    if find "$PROJECT_ROOT/src" -maxdepth 3 -name "*.java" 2>/dev/null | head -1 | grep -q .; then
        echo "java"
    fi
    if find "$PROJECT_ROOT/src" -maxdepth 3 -name "*.kt" -o -name "*.kts" 2>/dev/null | head -1 | grep -q .; then
        echo "kotlin"
    fi
fi

# swift
if [ -f "$PROJECT_ROOT/Package.swift" ]; then
    echo "swift"
fi

# dart
if [ -f "$PROJECT_ROOT/pubspec.yaml" ]; then
    echo "dart"
fi

# zig
if [ -f "$PROJECT_ROOT/build.zig" ]; then
    echo "zig"
fi

# go
if [ -f "$PROJECT_ROOT/go.mod" ]; then
    echo "go"
fi

# elixir
if [ -f "$PROJECT_ROOT/mix.exs" ]; then
    echo "elixir"
fi
