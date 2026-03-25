Use `uv` for dependency management. Commit `uv.lock`. `pyproject.toml` for all projects.
Format with `ruff format` (line length 100). Lint with `ruff check`. Never use `black` or `isort` separately.
Type-check with `mypy` or `pyright` strict mode — zero errors required.
All functions, methods, and class attributes require explicit type annotations (including private).
No `# type: ignore` without a comment and linked issue. No `Any` without justification.
Use `list[str]` over `List[str]` (3.9+). Use `|` union syntax over `Union` (3.10+).
Naming: `snake_case` variables/functions/modules, `PascalCase` classes, `UPPER_SNAKE_CASE` constants.
Test with `pytest` + `pytest-cov`. 95% minimum coverage, 100% for domain.
Custom exceptions inherit from a domain base exception. Never use bare `except:`. Use `raise ... from` for chaining.
Security: run `bandit -r src/` and `pip-audit` in CI. Banned: `eval()`, `exec()`, `pickle.loads()` (untrusted), `yaml.load()`, `os.system()`, `subprocess.call(..., shell=True)`.
