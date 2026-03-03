# Ruby on Rails Standards

> **Prerequisite:** `standards/languages/lang-10_ruby_standards.md` -- all base Ruby standards apply. This document covers Rails-specific conventions and extensions.

## 1. Rails Version

* **Minimum:** Rails 7.2+.
* **Linter:** `rubocop-rails` gem required in addition to base `rubocop`.
* **Config:** Add the following to your `.rubocop.yml`:

```yaml
require:
  - rubocop-rails
  - rubocop-rspec
  - rubocop-performance

AllCops:
  TargetRubyVersion: 3.2
  NewCops: enable
  Exclude:
    - "db/schema.rb"
    - "db/migrate/**/*"
    - "bin/**/*"
    - "vendor/**/*"
    - "node_modules/**/*"
    - "tmp/**/*"

Rails:
  Enabled: true
```

## 2. Class Structure

Rails models MUST follow this ordering. This is enforced by `Layout/ClassStructure` in RuboCop.

| Order | Category | Examples |
|-------|----------|----------|
| 1 | Module inclusions | `include`, `prepend`, `extend`, `require` |
| 2 | Gem configuration | `devise`, `searchkick`, `sidekiq_options`, `mount_uploader`, `audited`, `acts_as_paranoid`, etc. |
| 3 | Constants | `ROLES = %w[admin member guest].freeze` |
| 4 | Attributes | `attribute`, `attr_reader`, `attr_writer`, `attr_accessor`, `alias_attribute` |
| 5 | Enums | `enum` |
| 6 | Serializers | `serialize` |
| 7 | Associations | `has_one`, `has_many`, `belongs_to`, `has_and_belongs_to_many`, `delegate` |
| 8 | Nested attributes | `accepts_nested_attributes_for` |
| 9 | Scopes | `scope` |
| 10 | Validations | `validate`, `validates`, `validates_with`, `validates_each` |
| 11 | Hooks/Callbacks | `before_validation`, `after_validation`, `before_save`, `after_save`, `before_create`, `after_create`, `before_update`, `after_update`, `before_destroy`, `after_destroy`, `after_commit` |
| 12 | Public class methods | `self.method_name` |
| 13 | Initializer | `initialize` |
| 14 | Public methods | Instance methods (default visibility) |
| 15 | Protected methods | Methods under `protected` |
| 16 | Private methods | Methods under `private` |

### Full User Model Example

```ruby
# typed: strict
# frozen_string_literal: true

class User < ApplicationRecord
  extend T::Sig

  # 1. Module inclusions
  include Auditable
  include Searchable

  # 2. Gem configuration
  devise :database_authenticatable, :registerable, :recoverable,
         :rememberable, :validatable, :confirmable
  searchkick word_start: [:name, :email]

  # 3. Constants
  ROLES = T.let(%w[admin member guest].freeze, T::Array[String])
  MAX_LOGIN_ATTEMPTS = T.let(5, Integer)

  # 4. Attributes
  attribute :preferences, :jsonb, default: {}
  attr_accessor :skip_welcome_email

  # 5. Enums
  enum :role, { admin: 0, member: 1, guest: 2 }, default: :member
  enum :status, { active: 0, inactive: 1, suspended: 2 }, default: :active

  # 6. Serializers
  serialize :settings, coder: JSON

  # 7. Associations
  belongs_to :organization, optional: true
  has_one :profile, dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :notifications, dependent: :delete_all
  delegate :name, to: :organization, prefix: true, allow_nil: true

  # 8. Nested attributes
  accepts_nested_attributes_for :profile, update_only: true

  # 9. Scopes
  scope :active, -> { where(status: :active) }
  scope :admins, -> { where(role: :admin) }
  scope :recently_active, -> { where(last_sign_in_at: 30.days.ago..) }
  scope :searchable, -> { active.where.not(confirmed_at: nil) }

  # 10. Validations
  validates :name, presence: true, length: { maximum: 100 }
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :role, inclusion: { in: ROLES }
  validates :login_attempts, numericality: {
    less_than_or_equal_to: MAX_LOGIN_ATTEMPTS,
  }

  # 11. Hooks/Callbacks
  before_validation :normalize_email, on: :create
  after_create :send_welcome_email, unless: :skip_welcome_email
  after_update :notify_profile_change, if: :saved_change_to_name?

  # 12. Public class methods
  sig { params(email: String).returns(T.nilable(User)) }
  def self.find_by_normalized_email(email)
    find_by(email: email.downcase.strip)
  end

  # 13. (No custom initializer needed -- ActiveRecord handles it)

  # 14. Public methods
  sig { returns(String) }
  def display_name
    name.presence || email.split("@").first
  end

  sig { returns(T::Boolean) }
  def admin?
    role == "admin"
  end

  sig { returns(T::Boolean) }
  def can_post?
    active? && confirmed_at.present?
  end

  # 15. Protected methods
  protected

  sig { returns(T::Boolean) }
  def password_required?
    super && provider.blank?
  end

  # 16. Private methods
  private

  sig { void }
  def normalize_email
    self.email = email.downcase.strip if email.present?
  end

  sig { void }
  def send_welcome_email
    UserMailer.welcome(self).deliver_later
  end

  sig { void }
  def notify_profile_change
    NotificationService.call(user: self, event: :profile_updated)
  end
end
```

## 3. Model Conventions

* **Validations:** Use `validates` (declarative) over `validate` (custom method) whenever possible. Reserve `validate` for complex multi-field validations.
* **Scopes:** Name scopes as adjectives or descriptive noun phrases: `active`, `published`, `recently_active`, `with_comments`. Avoid verb prefixes like `get_` or `find_`.
* **Callbacks:** Minimize callbacks. Prefer service objects for complex side effects. Callbacks are acceptable for simple data normalization (`before_validation`) and cache invalidation. Never use callbacks for business logic that spans multiple models.
* **belongs_to:** Not required by default. Use `optional: true` explicitly when the association is truly optional. Configure globally:

```ruby
# config/application.rb
config.active_record.belongs_to_required_by_default = false
```

* **Enum syntax:** Always use the hash syntax with explicit integer mapping:

```ruby
# Good -- explicit values, safe to reorder
enum :status, { draft: 0, published: 1, archived: 2 }

# Bad -- implicit values, reordering breaks data
enum :status, [:draft, :published, :archived]
```

* **Concerns:** Use concerns sparingly. Extract to modules in `app/models/concerns/` only when behavior is genuinely shared across 3+ models.

## 4. Controller Conventions

* **Strong parameters:** Always use strong params via a private method. Never use `params.permit!`.
* **before_action:** Use `before_action` for authentication, authorization, and resource loading. Specify `only:` or `except:` to limit scope.
* **Thin controllers:** Controllers should delegate business logic to service objects or use cases. Controller actions should be 5-10 lines max.
* **RESTful:** Stick to the 7 RESTful actions (`index`, `show`, `new`, `create`, `edit`, `update`, `destroy`). Add custom actions only when necessary and nest them under the resource.

### UsersController Example

```ruby
# typed: strict
# frozen_string_literal: true

class UsersController < ApplicationController
  extend T::Sig

  before_action :authenticate_user!
  before_action :set_user, only: [:show, :edit, :update, :destroy]
  before_action :authorize_user!, only: [:edit, :update, :destroy]

  sig { void }
  def index
    @users = T.let(
      User.active.order(created_at: :desc).page(params[:page]),
      T.nilable(T.untyped),
    )
  end

  sig { void }
  def show; end

  sig { void }
  def create
    result = CreateUser.call(params: user_params, created_by: current_user)

    if result.success?
      redirect_to result.user, notice: "User created successfully."
    else
      @user = T.let(result.user, T.nilable(User))
      render :new, status: :unprocessable_entity
    end
  end

  sig { void }
  def update
    result = UpdateUser.call(user: @user, params: user_params)

    if result.success?
      redirect_to @user, notice: "User updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  sig { void }
  def destroy
    @user.destroy
    redirect_to users_path, notice: "User deleted."
  end

  private

  sig { void }
  def set_user
    @user = T.let(User.find(params[:id]), T.nilable(User))
  end

  sig { void }
  def authorize_user!
    authorize @user
  end

  sig { returns(ActionController::Parameters) }
  def user_params
    params.require(:user).permit(:name, :email, :role, :organization_id)
  end
end
```

## 5. Service Objects

* **Location:** `app/application/use_cases/` (preferred for DDD) or `app/services/`.
* **Interface:** Single public `.call` class method. Accept keyword arguments.
* **Naming:** Use verb phrases: `CreateUser`, `SendInvoice`, `ProcessPayment`, `SyncInventory`.
* **Return value:** Return a result object (not raw model) so callers can check `success?`.

### CreateUser Example

```ruby
# typed: strict
# frozen_string_literal: true

class CreateUser
  extend T::Sig

  class Result < T::Struct
    const :success, T::Boolean
    const :user, T.nilable(User)
    const :errors, T::Array[String], default: []

    sig { returns(T::Boolean) }
    def success? = success
  end

  sig { params(params: T::Hash[Symbol, T.untyped], created_by: User).returns(Result) }
  def self.call(params:, created_by:)
    new(params: params, created_by: created_by).call
  end

  sig { params(params: T::Hash[Symbol, T.untyped], created_by: User).void }
  def initialize(params:, created_by:)
    @params = params
    @created_by = created_by
  end

  sig { returns(Result) }
  def call
    user = User.new(@params)
    user.invited_by = @created_by

    if user.save
      send_welcome_email(user)
      track_creation(user)
      Result.new(success: true, user: user)
    else
      Result.new(success: false, user: user, errors: user.errors.full_messages)
    end
  end

  private

  sig { params(user: User).void }
  def send_welcome_email(user)
    SendWelcomeEmailJob.perform_later(user_id: user.id)
  end

  sig { params(user: User).void }
  def track_creation(user)
    Analytics.track(event: "user_created", user_id: user.id, created_by: @created_by.id)
  end
end
```

## 6. Testing (Rails-Specific)

* **Request specs** over controller specs. Controller specs are deprecated in modern Rails testing.
* **Model specs:** Test validations, scopes, associations, and public methods.
* **System specs:** Use Capybara for end-to-end browser testing. Use `driven_by(:selenium_chrome_headless)`.
* **Factories:** Use `factory_bot` for test data. Never use fixtures for new tests.
* **Database:** Use `database_cleaner` with transaction strategy for speed. Use truncation strategy for system specs.
* **Coverage:** 95% minimum for models, services, and controllers. 100% for domain.

### Request Spec Example

```ruby
# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Users", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }

  before { sign_in admin }

  describe "GET /users" do
    it "returns a successful response" do
      get users_path

      expect(response).to have_http_status(:ok)
    end

    it "lists active users" do
      active_user = create(:user, :active)
      inactive_user = create(:user, :inactive)

      get users_path

      expect(response.body).to include(active_user.name)
      expect(response.body).not_to include(inactive_user.name)
    end
  end

  describe "POST /users" do
    let(:valid_params) do
      { user: { name: "Jane Doe", email: "jane@example.com", role: "member" } }
    end

    it "creates a user and redirects" do
      expect {
        post users_path, params: valid_params
      }.to change(User, :count).by(1)

      expect(response).to redirect_to(User.last)
      follow_redirect!
      expect(response.body).to include("User created successfully.")
    end

    it "enqueues a welcome email job" do
      expect {
        post users_path, params: valid_params
      }.to have_enqueued_job(SendWelcomeEmailJob)
    end

    context "with invalid params" do
      let(:invalid_params) { { user: { name: "", email: "" } } }

      it "returns unprocessable entity and re-renders form" do
        post users_path, params: invalid_params

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /users/:id" do
    it "deletes the user and redirects" do
      user_to_delete = create(:user)

      expect {
        delete user_path(user_to_delete)
      }.to change(User, :count).by(-1)

      expect(response).to redirect_to(users_path)
    end
  end
end
```

## 7. Database

* **Migrations:** Always use `rails generate migration` to create migration files. Never hand-create migration files.
* **schema.rb:** Never edit `db/schema.rb` directly. It is auto-generated. Exclude from RuboCop.
* **Environments:** Maintain separate database configurations for: `development`, `test`, `staging`, `demo`, `production`.
* **Foreign keys:** Always add database-level foreign keys and index them:

```ruby
class AddOrganizationToUsers < ActiveRecord::Migration[7.2]
  def change
    add_reference :users, :organization, null: true, foreign_key: true, index: true
  end
end
```

* **Database-level constraints:** Use database constraints (NOT NULL, UNIQUE, CHECK) in addition to model validations. The database is the last line of defense:

```ruby
class CreateUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.integer :role, null: false, default: 1
      t.integer :status, null: false, default: 0
      t.integer :login_attempts, null: false, default: 0
      t.references :organization, foreign_key: true, index: true

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :role
    add_index :users, :status
  end
end
```

* **Large migrations:** For data migrations on large tables, use batching (`find_each`, `in_batches`) and run outside of schema migrations when possible.

## 8. Background Jobs

* **Queue backend:** Sidekiq.
* **Location:** `app/jobs/`.
* **Base class:** All jobs inherit from `ApplicationJob`.
* **Idempotency:** Jobs MUST be idempotent. They may be retried on failure. Use unique job IDs or database checks to prevent duplicate processing.
* **Arguments:** Pass primitive types (IDs, strings) as job arguments, never full ActiveRecord objects.

### SendWelcomeEmailJob Example

```ruby
# typed: strict
# frozen_string_literal: true

class SendWelcomeEmailJob < ApplicationJob
  extend T::Sig

  queue_as :default
  retry_on Net::SMTPError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveJob::DeserializationError

  sig { params(user_id: Integer).void }
  def perform(user_id:)
    user = User.find_by(id: user_id)
    return if user.nil?
    return if user.welcome_email_sent_at.present?

    UserMailer.welcome(user).deliver_now
    user.update!(welcome_email_sent_at: Time.current)
  end
end
```

## 9. Security

* **CSRF protection:** Enabled by default via `protect_from_forgery with: :exception` in `ApplicationController`. Never disable it for non-API controllers.
* **Strong parameters:** Always use strong params. Never call `params.permit!` or mass-assign unfiltered input.
* **Safe navigation:** Use `&.` (safe navigation operator) instead of `try` or `try!`:

```ruby
# Good
user&.profile&.avatar_url

# Bad
user.try(:profile).try(:avatar_url)
```

* **Parameterized queries:** Never interpolate user input into SQL. Always use parameterized queries or ActiveRecord's query interface:

```ruby
# Good
User.where(email: params[:email])
User.where("name ILIKE ?", "%#{User.sanitize_sql_like(params[:q])}%")

# Bad -- SQL injection vulnerability
User.where("email = '#{params[:email]}'")
```

* **Rails credentials:** Use `rails credentials:edit` for secrets. Never commit secrets to version control. Never store secrets in environment variables checked into `.env` files in the repository.
* **Content Security Policy:** Configure CSP headers in `config/initializers/content_security_policy.rb`.
* **Brakeman:** Run `brakeman` in CI to scan for security vulnerabilities.

## 10. RuboCop Configuration

Key Rails-specific RuboCop decisions for this project. Reference `standards/agents/ruby/.rubocop.yml` for the full configuration file.

```yaml
# Layout/ClassStructure -- enforce the ordering defined in Section 2
# See `standards/agents/ruby/.rubocop.yml` for the full `Layout/ClassStructure`
# configuration matching the 16-level ordering described in Section 2.

# Never enforce hash rocket vs. symbol style -- allow both
Style/HashSyntax:
  Enabled: never

# Do not count hash/method_call lines toward method length
Metrics/MethodLength:
  CountAsOne:
    - hash
    - method_call

# Exclude spec files from block and module length checks
Metrics/BlockLength:
  Exclude:
    - "spec/**/*"
    - "config/**/*"
    - "db/**/*"

Metrics/ModuleLength:
  Exclude:
    - "spec/**/*"

# belongs_to is not required by default in our config
Rails/RedundantPresenceValidationOnBelongsTo:
  Enabled: false

# We do not enforce I18n for all user-facing text
Rails/I18nLocaleTexts:
  Enabled: false

# Gemfile ordering is managed by bundler groups, not alphabetically
Bundler/OrderedGems:
  Enabled: false
```
