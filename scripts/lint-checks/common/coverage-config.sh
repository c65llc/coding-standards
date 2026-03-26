#!/bin/bash
# Check: verify CI has coverage gates configured
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="coverage-config"

FOUND=""

# Check GitHub Actions workflows for coverage mentions
if [ -d "$PROJECT_ROOT/.github/workflows" ]; then
    workflow_coverage=$(grep -rlE 'coverage|codecov|coveralls' "$PROJECT_ROOT/.github/workflows/" 2>/dev/null || true)
    if [ -n "$workflow_coverage" ]; then
        workflow_name=$(basename "$(echo "$workflow_coverage" | head -1)")
        FOUND="Coverage step found in GitHub Actions ($workflow_name)"
    fi
fi

# Check pytest coverage config in pyproject.toml
if [ -z "$FOUND" ] && [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
    if grep -qE '\[tool\.pytest|coverage\]|\[tool\.coverage' "$PROJECT_ROOT/pyproject.toml" 2>/dev/null; then
        FOUND="Coverage config found in pyproject.toml"
    fi
fi

# Check pytest.ini for coverage
if [ -z "$FOUND" ] && [ -f "$PROJECT_ROOT/pytest.ini" ]; then
    if grep -qE '(addopts|cov|coverage)' "$PROJECT_ROOT/pytest.ini" 2>/dev/null; then
        FOUND="Coverage config found in pytest.ini"
    fi
fi

# Check setup.cfg for coverage
if [ -z "$FOUND" ] && [ -f "$PROJECT_ROOT/setup.cfg" ]; then
    if grep -qE '\[coverage|cov_min|fail_under' "$PROJECT_ROOT/setup.cfg" 2>/dev/null; then
        FOUND="Coverage config found in setup.cfg"
    fi
fi

# Check jest.config for coverage thresholds
if [ -z "$FOUND" ]; then
    for jest_cfg in jest.config.js jest.config.ts jest.config.mjs jest.config.cjs jest.config.json; do
        if [ -f "$PROJECT_ROOT/$jest_cfg" ]; then
            if grep -qE 'coverageThreshold|collectCoverage' "$PROJECT_ROOT/$jest_cfg" 2>/dev/null; then
                FOUND="Coverage threshold found in $jest_cfg"
                break
            fi
        fi
    done
fi

# Check package.json jest config
if [ -z "$FOUND" ] && [ -f "$PROJECT_ROOT/package.json" ]; then
    if grep -qE 'coverageThreshold|collectCoverage' "$PROJECT_ROOT/package.json" 2>/dev/null; then
        FOUND="Coverage config found in package.json (jest)"
    fi
fi

# Check .nycrc or nyc config in package.json
if [ -z "$FOUND" ]; then
    for nyc_cfg in .nycrc .nycrc.json; do
        if [ -f "$PROJECT_ROOT/$nyc_cfg" ]; then
            FOUND="Coverage config found in $nyc_cfg"
            break
        fi
    done
fi

# Check codecov.yml
if [ -z "$FOUND" ]; then
    for codecov_cfg in codecov.yml .codecov.yml codecov.yaml; do
        if [ -f "$PROJECT_ROOT/$codecov_cfg" ]; then
            FOUND="Coverage config found in $codecov_cfg"
            break
        fi
    done
fi

# Check .standards.yml for coverage settings
if [ -z "$FOUND" ] && [ -f "$PROJECT_ROOT/.standards.yml" ]; then
    if grep -qE '^coverage:' "$PROJECT_ROOT/.standards.yml" 2>/dev/null; then
        cov_min=$(grep -A2 '^coverage:' "$PROJECT_ROOT/.standards.yml" 2>/dev/null | grep 'minimum:' | sed 's/.*minimum:[[:space:]]*//' | tr -d ' ')
        if [ -n "$cov_min" ]; then
            FOUND="Coverage gate found in .standards.yml (minimum: ${cov_min}%)"
        fi
    fi
fi

if [ -n "$FOUND" ]; then
    echo "PASS $CHECK_NAME $FOUND"
    exit 0
else
    echo "FAIL $CHECK_NAME No coverage configuration found in CI workflows, test config, or .standards.yml"
    exit 1
fi
