# Python Standards

## 1. Package Management

* **Tool:** `uv` for dependency management, virtual environments, and Python version management. Prefer `uv` over `poetry` or naked `pip`. Lock files committed.
* **Virtual Environments:** Always use isolated environments (`uv venv`). Never install globally.
* **Requirements:** `pyproject.toml` for all projects. `requirements.txt` only for legacy compatibility.

## 2. Code Style

* **Formatter:** `ruff format` with line length 100. Prefer `ruff format` over `black` — it is faster, compatible with Black's style, and consolidates formatting and linting into a single tool. Integrate `ruff format` into the project's standard formatting command (e.g., `make fmt`).
* **Linter:** `ruff check` for fast, comprehensive linting. Replaces `pylint`, `isort`, `pyflakes`, and `pycodestyle`.
* **Type Checker:** `mypy` or `pyright` in **strict mode** with zero errors. See Section 4 for full typing requirements.

### Configuration

```toml
[tool.ruff]
line-length = 100
target-version = "py311"

[tool.ruff.lint]
select = ["E", "F", "I", "N", "W", "UP"]

[tool.ruff.format]
# Compatible with Black style

[tool.mypy]
strict = true
warn_return_any = true
warn_unused_configs = true
```

## 3. Naming Conventions

* **Modules:** `snake_case.py`
* **Classes:** `PascalCase`
* **Functions/Variables:** `snake_case`
* **Constants:** `UPPER_SNAKE_CASE`
* **Private:** `_single_leading_underscore` (module-level)
* **Name Mangling:** `__double_leading_underscore` (class-level, avoid unless necessary)

## 4. Type Hints — All Code Must Be Strongly Typed

**Python code MUST be strongly typed throughout. This is not limited to public APIs — every function, method, variable declaration, class attribute, and return type requires explicit type annotations.**

### Requirements

* **All functions and methods:** Parameter types and return types are mandatory — no exceptions. This includes private/internal functions.
* **Variables:** Annotate variables when the type is not obvious from assignment. Always annotate empty collections, `None`-initialized variables, and class attributes.
* **mypy strict mode:** Must pass with zero errors. The following `pyproject.toml` configuration is mandatory:

  ```toml
  [tool.mypy]
  strict = true
  warn_return_any = true
  warn_unused_configs = true
  disallow_untyped_defs = true
  disallow_incomplete_defs = true
  check_untyped_defs = true
  disallow_any_generics = true
  no_implicit_optional = true
  warn_redundant_casts = true
  warn_unused_ignores = true
  ```

* **No `# type: ignore`** without an accompanying comment explaining why and a linked issue for resolution.
* **No `Any`** without explicit justification in a comment. Prefer `object` or `Unknown` patterns.
* **Style:** Prefer `list[str]` over `List[str]` (Python 3.9+). Use `|` union syntax over `Union` (Python 3.10+).
* **Protocols:** Use `Protocol` for structural subtyping instead of ABCs when appropriate.
* **Generics:** Use `TypeVar` and `Generic` for reusable type parameters.

### Example

```python
from typing import Protocol, TypeVar

T = TypeVar("T")

class Repository(Protocol[T]):
    def find_by_id(self, id: str) -> T | None: ...
    def save(self, entity: T) -> None: ...

# All functions — including private ones — must be fully typed
def _validate_email(email: str) -> bool:
    return "@" in email

class UserService:
    _cache: dict[str, User]  # Class attributes must be typed

    def __init__(self, repo: Repository[User]) -> None:
        self._cache = {}
```

## 5. Project Structure

```text
package_name/
├── __init__.py
├── domain/
│   ├── __init__.py
│   ├── entities.py
│   └── value_objects.py
├── application/
│   ├── __init__.py
│   ├── use_cases.py
│   └── interfaces.py
└── infrastructure/
    ├── __init__.py
    └── repositories.py
```

## 6. Testing

* **Methodology:** **Test-Driven Development (TDD) is mandatory.** Write failing tests before implementation code.
* **Framework:** `pytest`. Use fixtures for test dependencies.
* **Coverage:** `pytest-cov`. **95% is the absolute minimum for any module.** Target 100% for domain, 95%+ for application and infrastructure.
* **Regression:** Every bug fix must include a regression test.
* **Mocking:** `unittest.mock` or `pytest-mock`. Mock external dependencies only.
* **Local full-stack:** Tests must be runnable locally without external dependencies. Use `testcontainers` or in-memory substitutes.

### Test Structure

```python
# tests/domain/test_user.py
import pytest
from domain.entities import User

def test_should_create_user_with_valid_email():
    user = User(email="test@example.com", name="Test User")
    assert user.email == "test@example.com"
```

## 7. Error Handling

* **Custom Exceptions:** Define in domain layer. Inherit from domain base exception.
* **Type:** Use typed exceptions. No bare `except:` clauses.
* **Context:** Use `raise ... from` for exception chaining.

```python
class DomainError(Exception):
    """Base exception for domain layer."""
    pass

class InvalidEmailError(DomainError):
    """Raised when email validation fails."""
    pass
```

## 8. Async/Await

* **Use When:** I/O-bound operations (database, HTTP, file operations).
* **Framework:** `asyncio` for core, `aiohttp`/`httpx` for HTTP, `asyncpg`/`aiomysql` for databases.
* **Type Hints:** Use `Coroutine`, `Awaitable` for return types.

## 9. Dependencies

### Common Libraries

* **HTTP:** `httpx` (async), `requests` (sync)
* **Database:** `sqlalchemy` (ORM), `asyncpg` (async PostgreSQL)
* **Validation:** `pydantic` for data validation and settings
* **Logging:** `structlog` for structured logging

## 10. Documentation

* **Docstrings:** Google or NumPy style. Required for all public classes and functions.
* **Type Info:** Type hints preferred over docstring type annotations.
* **Examples:** Include usage examples in docstrings for complex functions.

```python
def create_user(email: str, name: str) -> User:
    """Create a new user with validated email.

    Args:
        email: Valid email address.
        name: User's full name.

    Returns:
        User entity instance.

    Raises:
        InvalidEmailError: If email format is invalid.

    Example:
        >>> user = create_user("test@example.com", "John Doe")
        >>> user.email
        'test@example.com'
    """
    # Implementation
```

## 11. Security

> Full security standards: `standards/security/sec-01_security_standards.md`

- **SAST:** Run `bandit -r src/` in CI. Configure with `.bandit` or `pyproject.toml`.
- **Dependency scanning:** Run `pip-audit` in CI. Optionally, you may also run `safety check` if your organization uses Safety; the newer `safety scan` command requires a Safety CLI account and is not the default recommendation.
- **Secrets scanning:** Use `detect-secrets` as a pre-commit hook.
- **Banned functions:** `eval()`, `exec()`, `pickle.loads()` (untrusted), `yaml.load()` (use `safe_load`), `os.system()`, `subprocess.call(..., shell=True)`.
- **Secure random:** Use `secrets` module for tokens and keys, not `random`.
