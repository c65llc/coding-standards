# Ruby Standards

## 1. Package Management

* **Gems:** `bundler`. `Gemfile.lock` committed. Pin exact versions for production dependencies.
* **Ruby Version:** Ruby 3.2+. Use `mise` for version management. Specify version in `.ruby-version`.
* **Config:** `Gemfile` for all projects. Group gems by environment (`:development`, `:test`, `:production`).

## 2. Code Style

* **Linter/Formatter:** `rubocop`. Run via `make lint` or `bundle exec rubocop`.
* **Auto-correct:** `rubocop -A` for safe auto-corrections. Run via `make fmt`.
* **Config:** `.rubocop.yml` at project root. Enable `NewCops`.

### .rubocop.yml (base)

```yaml
AllCops:
  NewCops: enable
  SuggestExtensions: false
  Exclude:
    - 'bin/**/*'
    - 'script/**/*'

Style/Documentation:
  Enabled: false

Style/HashSyntax:
  EnforcedShorthandSyntax: never

Layout/MultilineMethodCallIndentation:
  EnforcedStyle: indented

Layout/FirstHashElementIndentation:
  EnforcedStyle: consistent
```

## 3. Naming Conventions

* **Files:** `snake_case.rb`
* **Classes/Modules:** `PascalCase` (CamelCase)
* **Methods/Variables:** `snake_case`
* **Constants:** `UPPER_SNAKE_CASE`
* **Predicates:** `?` suffix — `active?`, `valid_email?`
* **Dangerous methods:** `!` suffix — `save!`, `destroy!`
* **Private:** No prefix convention. Use `private` keyword.

## 4. Type Safety — Sorbet

**Ruby code MUST use Sorbet for static typing. This is not optional — every file must include a typed sigil and every method must have a signature.**

### Requirements

* **Typed sigil:** All files must have `# typed: strict` at the top.
* **Method signatures:** All methods must have `sig` annotations — no exceptions.
* **Variables:** Use `T.let` for variables where the type is ambiguous.
* **Nullable:** Use `T.nilable(Type)` for nullable values.
* **No `T.untyped`** without explicit justification in a comment.
* **RBI generation:** Use `tapioca` for generating RBI files. Store in `sorbet/rbi/`.

### sorbet/config

```text
--dir
.
--ignore=vendor/
```

### Example

```ruby
# typed: strict
# frozen_string_literal: true

class Email
  extend T::Sig

  sig { returns(String) }
  attr_reader :value

  sig { params(value: String).void }
  def initialize(value)
    raise InvalidEmailError, value unless value.include?('@') && value.include?('.')

    @value = T.let(value, String)
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
    other.is_a?(Email) && other.value == value
  end

  sig { returns(String) }
  def to_s
    value
  end
end
```

## 5. Project Structure

```text
app/
├── domain/
│   ├── entities/
│   │   └── email.rb
│   └── value_objects/
│       └── money.rb
├── application/
│   ├── use_cases/
│   │   └── create_user.rb
│   └── interfaces/
│       └── user_repository.rb
├── infrastructure/
│   ├── repositories/
│   │   └── pg_user_repository.rb
│   └── adapters/
│       └── stripe_adapter.rb
lib/
├── core_ext/
│   └── string.rb
└── utils/
    └── validator.rb
spec/
├── domain/
│   └── entities/
│       └── email_spec.rb
├── application/
│   └── use_cases/
│       └── create_user_spec.rb
└── spec_helper.rb
```

## 6. Testing

* **Methodology:** **Test-Driven Development (TDD) is mandatory.** Write failing tests before implementation code.
* **Framework:** `rspec`. Use `let` and `subject` for test setup. Prefer `describe`/`context`/`it` blocks.
* **Factories:** `factory_bot` for test data. No fixtures — use factories exclusively.
* **Matchers:** `shoulda-matchers` for common Rails matchers.
* **Coverage:** `simplecov`. **95% is the absolute minimum for any module.** Target 100% for domain, 95%+ for application and infrastructure.
* **Regression:** Every bug fix must include a regression test.

### Test Structure

```ruby
# spec/domain/entities/email_spec.rb
# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Email do
  describe '#initialize' do
    context 'with a valid email' do
      subject { described_class.new('user@example.com') }

      it 'creates an email' do
        expect(subject.value).to eq('user@example.com')
      end
    end

    context 'with an invalid email' do
      it 'raises InvalidEmailError' do
        expect { described_class.new('invalid') }.to raise_error(InvalidEmailError)
      end
    end
  end
end
```

## 7. Error Handling

* **Custom Exceptions:** Define in domain layer. Inherit from a domain base exception.
* **No bare `rescue`:** Always specify the exception class. Never use `rescue => e` without a type.
* **Exception chaining:** Wrap lower-level errors with domain-specific exceptions.

```ruby
# typed: strict
# frozen_string_literal: true

class DomainError < StandardError
  extend T::Sig

  sig { returns(T.nilable(Exception)) }
  attr_reader :cause

  sig { params(message: String, cause: T.nilable(Exception)).void }
  def initialize(message, cause: nil)
    super(message)
    @cause = T.let(cause, T.nilable(Exception))
  end
end

class InvalidEmailError < DomainError
  extend T::Sig

  sig { params(email: String).void }
  def initialize(email)
    super("Invalid email address: #{email}")
  end
end
```

## 8. Documentation

* **Format:** YARD. Required for all public classes and methods.
* **Type Info:** Sorbet `sig` blocks are the source of truth for types. YARD `@param` and `@return` tags supplement with descriptions.
* **Examples:** Include usage examples for complex methods.

```ruby
# typed: strict
# frozen_string_literal: true

class UserService
  extend T::Sig

  # Creates a new user with a validated email address.
  #
  # @param email [String] valid email address (must contain @ and .)
  # @param name [String] user's full name (non-empty)
  # @return [User] newly created user entity
  # @raise [InvalidEmailError] if the email format is invalid
  # @raise [DuplicateUserError] if a user with this email already exists
  #
  # @example
  #   service = UserService.new(repo)
  #   user = service.create_user("test@example.com", "John Doe")
  #   user.email #=> "test@example.com"
  #
  sig { params(email: String, name: String).returns(User) }
  def create_user(email, name)
    # Implementation
  end
end
```

## 9. Dependencies

### Common Gems

* **HTTP:** `faraday` (client with middleware), `httparty` (simple HTTP)
* **Database:** `pg` (PostgreSQL driver), `sequel` (lightweight ORM), `rom-rb` (data mapper)
* **Serialization:** `oj` (fast JSON)
* **Background Jobs:** `sidekiq` for async job processing
* **Logging:** `semantic_logger` for structured logging
* **Type Safety:** `sorbet` (runtime), `tapioca` (RBI generation)

## 10. Async

* **Thread Safety:** `concurrent-ruby` for thread-safe data structures (`Concurrent::Hash`, `Concurrent::Array`, `Concurrent::Future`).
* **Fiber Scheduler:** Ruby 3.0+ Fiber Scheduler for non-blocking I/O. Use `Async` gem for structured concurrency.
* **Background Jobs:** `sidekiq` for background job processing. Keep jobs idempotent and small.

```ruby
# typed: strict
# frozen_string_literal: true

require 'concurrent'

class FetchUsersService
  extend T::Sig

  sig { params(ids: T::Array[String]).returns(T::Array[User]) }
  def fetch_all(ids)
    futures = ids.map do |id|
      Concurrent::Future.execute { fetch_user(id) }
    end

    futures.map(&:value!)
  end

  private

  sig { params(id: String).returns(User) }
  def fetch_user(id)
    # Implementation
  end
end
```
