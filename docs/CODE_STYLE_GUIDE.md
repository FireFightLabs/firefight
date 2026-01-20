# FireFight Code Style Guide

This document describes the architectural patterns, conventions, and code style that FireFight follows.

---

## Table of Contents

1. [Architecture Philosophy](#architecture-philosophy)
2. [Layer Responsibilities](#layer-responsibilities)
3. [Logging Standards](#logging-standards)
4. [Naming Conventions](#naming-conventions)
5. [Error Handling](#error-handling)
6. [Testing Approach](#testing-approach)

---

## Architecture Philosophy

FireFight follows a hybrid approach inspired by 37signals/Basecamp patterns, adapted for multi-platform integration:

### Core Principles

1. **Heavy Models** - Domain logic lives in models when it's data-centric
2. **Slim Controllers** - Controllers delegate to services, handle HTTP concerns only
3. **Services for Business Logic** - Platform-agnostic reusable business logic
4. **Adapters for Platform Code** - Platform-specific implementations (Slack, Teams)
5. **Thin Workflows** - Orchestration only, delegates to services
6. **No Business Logic in Adapters** - Adapters translate, services coordinate

### Why Not Pure 37signals?

37signals projects (like Basecamp, HEY) don't integrate with external platforms. FireFight does:
- **Slack integration** - requires platform-specific code
- **Teams integration** (future) - requires different platform-specific code
- **Adapters isolate platform differences** - business logic stays platform-agnostic

---

## Layer Responsibilities

### 1. Models (`app/models/`)

**Purpose:** Domain objects, data validation, database interactions

**What goes here:**
- Associations, validations, scopes
- Simple domain logic related to the model's data
- Class methods for finding/creating records
- Instance methods for querying/updating the record

**Example:**
```ruby
class Workspace < ApplicationRecord
  # Associations
  has_many :workspace_memberships

  # Validations
  validates :platform, :platform_id, :name, presence: true

  # Scopes
  scope :slack_platform, -> { where(platform: "slack") }

  # Class method - coordinates creation of related records
  def self.process_slack_installation(auth_hash)
    transaction do
      workspace = find_or_create_from_slack!(auth_hash)
      user = User.find_or_create_from_omniauth!(auth_hash)
      membership = WorkspaceMembership.find_or_create_from_omniauth!(user, workspace, auth_hash)

      {
        workspace: workspace,
        user: user,
        membership: membership,
        first_install: workspace.previously_new_record? || workspace.incidents_channel_id.blank?
      }
    end
  end

  # Instance method - simple query
  def token_expired?
    token_expires_at.present? && token_expires_at < Time.current
  end
end
```

**Don't put here:**
- Platform-specific code (Slack API calls, Teams API calls)
- Complex orchestration across multiple external services
- Workflow logic

---

### 2. Controllers (`app/controllers/`)

**Purpose:** HTTP request/response handling, minimal coordination

**What goes here:**
- Parse request parameters
- Delegate to services
- Set session/cookies
- Render responses or redirect
- Handle authentication/authorization

**Example:**
```ruby
class Auth::OmniauthCallbacksController < ApplicationController
  def slack
    auth_hash = request.env["omniauth.auth"]

    # Delegate to service
    service = SlackAuthenticationService.new
    result = service.process_oauth_callback(auth_hash)

    # HTTP concerns only
    session[:user_id] = result[:user].id
    session[:workspace_id] = result[:workspace].id

    notice = result[:first_install] ? "Setting up your FireFight workspace..." : "Successfully signed in!"
    redirect_to dashboard_path, notice: notice
  end
end
```

**Don't put here:**
- Business logic
- Direct adapter/client calls
- Database queries (call models/services instead)
- Multi-step orchestration

---

### 3. Services (`app/services/`)

**Purpose:** Platform-agnostic business logic, reusable across entry points

**What goes here:**
- Business logic that doesn't belong in models
- Coordination between models and adapters
- Workflow triggering logic
- Validation and error handling

**Why services exist:**
- Reusable from controllers, workflows, console, API
- Keep platform-agnostic logic separate from platform-specific code
- Coordinate complex operations

**Example:**
```ruby
class SlackAuthenticationService
  # Coordinates OAuth process and triggers workflow for new installs
  def process_oauth_callback(auth_hash)
    result = Workspace.process_slack_installation(auth_hash)

    if result[:first_install]
      trigger_workspace_setup(result[:workspace], auth_hash.uid)
    end

    result
  end

  private

  def trigger_workspace_setup(workspace, installer_user_id)
    Rails.logger.info({
      event: "slack_authentication.workspace_setup_triggered",
      message: "Triggering workspace setup workflow for first installation",
      workspace_id: workspace.id,
      installer_user_id: installer_user_id
    })

    SlackWorkspaceSetupWorkflow.start!(
      workspace,
      context: { installer_user_id: installer_user_id }
    )
  end
end
```

**Don't put here:**
- Platform-specific API calls (use adapters)
- HTTP/request handling (use controllers)
- Workflow step implementations (use workflows)

---

### 4. Adapters (`app/adapters/`)

**Purpose:** Platform-specific implementations with unified interface

**Structure:**
```
app/adapters/
  workspace_adapter.rb          # Factory for platform-specific adapters
  slack/
    client.rb                    # Low-level Slack API wrapper
    workspace_adapter.rb         # High-level workspace operations
    installation_message_builder.rb  # Slack Block Kit message builders
    token_manager.rb             # OAuth token refresh
    signature_verifier.rb        # Request signature verification
  teams/                         # Future: Microsoft Teams
    workspace_adapter.rb
```

**Factory Pattern:**
```ruby
# app/adapters/workspace_adapter.rb
class WorkspaceAdapter
  def self.for(workspace)
    case workspace.platform
    when "slack"
      Slack::WorkspaceAdapter.new(workspace)
    when "teams"
      Teams::WorkspaceAdapter.new(workspace)
    end
  end
end
```

**Platform-Specific Adapter:**
```ruby
module Slack
  class WorkspaceAdapter
    def initialize(workspace)
      @workspace = workspace
    end

    # High-level operation using message builder + client
    def post_welcome_message(channel_id:)
      message = Slack::InstallationMessageBuilder.welcome_message_blocks

      result = Slack::Client.post_message(
        workspace: @workspace,
        channel: channel_id,
        text: "Welcome to FireFight!",
        blocks: message[:blocks]
      )

      { message_ts: result[:ts] }
    end
  end
end
```

**What goes here:**
- Platform-specific API calls
- Message building (Block Kit for Slack, Adaptive Cards for Teams)
- Platform-specific error handling
- API response normalization

**Don't put here:**
- Business logic (when to post a message → service)
- Workflow orchestration
- Database operations

**Key Rule:** If Teams would need it differently → Adapter. If platform-agnostic → Service.

---

### 5. Workflows (`app/workflows/`)

**Purpose:** Orchestrate multi-step async processes with dependencies

**Built on:** SOLID workflow engine (custom, built for FireFight)

**Characteristics:**
- **Thin** - No business logic, just orchestration
- **Async** - Steps run in background jobs
- **Retryable** - Built-in retry with exponential backoff
- **Dependent** - Steps can depend on other steps
- **Stateful** - Track progress, store step outputs

**Example:**
```ruby
class SlackWorkspaceSetupWorkflow < Base
  workflow_name "slack.workspace_setup.v1"

  step :create_incidents_channel
  step :set_channel_metadata, depends_on: [:create_incidents_channel]
  step :post_welcome_message, depends_on: [:set_channel_metadata]
  step :invite_installer, depends_on: [:post_welcome_message]
  step :store_channel_id, depends_on: [:create_incidents_channel]

  def create_incidents_channel(workflow:, step:, input:)
    # Delegate to service - no business logic here
    setup_service.create_incidents_channel(workflow.subject)
  end

  def set_channel_metadata(workflow:, step:, input:)
    channel_id = input["create_incidents_channel"]["channel_id"]
    setup_service.set_channel_metadata(workflow.subject, channel_id)
  end

  # ... other steps

  private

  def setup_service
    @setup_service ||= WorkspaceSetupService.new
  end
end
```

**What goes here:**
- Step definitions with dependencies
- Calling service methods
- Extracting data from previous step outputs

**Don't put here:**
- Business logic (delegate to services)
- Direct adapter calls (use services)
- Complex data manipulation

**When to use workflows:**
- Multi-step processes that should run asynchronously
- Operations that need retry logic
- Processes with complex dependencies between steps
- Long-running operations (avoid blocking HTTP requests)

**When NOT to use workflows:**
- Simple, synchronous operations
- Single API calls
- Operations that must complete immediately

---

## Logging Standards

### Use Structured JSON Logging

**Always use:**
```ruby
Rails.logger.info({
  event: "namespace.action",           # Dot-separated event name
  message: "Human-readable description",
  workspace_id: workspace.id,
  user_id: user_id,
  # ... relevant context
})
```

**Never use:**
```ruby
# ❌ Don't do this
Rails.logger.info "User #{user_id} posted message"
Rails.logger.info("Modal submitted")
```

### Event Naming Convention

Format: `namespace.action` or `namespace.entity.action`

**Examples:**
- `workspace_setup.channel_created`
- `slack_authentication.workspace_setup_triggered`
- `interactions.preview_posted`
- `interactions.share_modal_opened`

### What to Log

**Always include:**
- `event` - Dot-separated event identifier
- `message` - Human-readable description
- Relevant IDs (workspace_id, user_id, etc.)
- Action-specific data

**Example:**
```ruby
Rails.logger.info({
  event: "interactions.channel_shared",
  message: "Shared incidents channel",
  workspace_id: workspace.id,
  user_id: user_id,
  target_count: result[:shared_count],
  targets: selected_conversations
})
```

### When to Log

- **Before triggering async operations** (workflows, jobs)
- **After completing operations** (if operation logs internally, skip)
- **On errors** (use `Rails.logger.error` or `Rails.logger.warn`)
- **Not during operations** (if service/adapter logs, don't duplicate)

---

## Naming Conventions

### Files and Classes

**Models:**
- File: `app/models/workspace.rb`
- Class: `Workspace`

**Controllers:**
- File: `app/controllers/api/v1/interactions_controller.rb`
- Class: `Api::V1::InteractionsController`

**Services:**
- File: `app/services/slack_authentication_service.rb`
- Class: `SlackAuthenticationService`
- Suffix: `Service`

**Adapters:**
- File: `app/adapters/slack/workspace_adapter.rb`
- Class: `Slack::WorkspaceAdapter`
- Suffix: `Adapter`

**Workflows:**
- File: `app/workflows/slack_workspace_setup_workflow.rb`
- Class: `SlackWorkspaceSetupWorkflow`
- Suffix: `Workflow`

### Methods

**Class methods:**
```ruby
def self.process_slack_installation(auth_hash)
  # Factory/coordination methods
end
```

**Instance methods:**
```ruby
def token_expired?
  # Query methods end with ?
end

def create_incidents_channel
  # Action methods use imperative verbs
end
```

**Private methods:**
```ruby
private

def find_workspace(payload)
  # Helper methods
end
```

### Variables

- Use descriptive names: `workspace`, `user_id`, `channel_id`
- Avoid abbreviations: `ws` → `workspace`
- Use snake_case: `installer_user_id`

---

## Error Handling

### Service Layer

```ruby
class SlackInteractionsService
  def handle_share_channel(payload)
    workspace = find_workspace(payload)
    # ... logic
  rescue Slack::Client::TriggerExpiredError
    Rails.logger.warn({
      event: "interactions.trigger_expired",
      message: "Trigger ID expired",
      workspace_id: workspace&.id
    })

    {
      response_action: "errors",
      errors: { base: "This interaction has expired. Please try again." }
    }
  end
end
```

### Controller Layer

```ruby
def slack
  # ... delegate to service
rescue => e
  Rails.logger.error("Slack OAuth failed: #{e.message}")
  Rails.logger.error(e.backtrace.join("\n"))
  redirect_to login_path, alert: "Authentication failed. Please try again."
end
```

### Custom Exceptions

Define in adapter/client:
```ruby
module Slack
  class Client
    class ApiError < StandardError; end
    class TriggerExpiredError < ApiError; end
    class ChannelExistsError < ApiError; end
  end
end
```

---

## Testing Approach

### Workflow Testing

Use `start_inline!` for synchronous execution in tests:
```ruby
workflow = SlackWorkspaceSetupWorkflow.start_inline!(
  workspace,
  context: { installer_user_id: "U12345" }
)

expect(workflow.state).to eq("succeeded")
```

### Console Testing

Test services and adapters in console:
```ruby
# Test service
service = SlackAuthenticationService.new
result = service.process_oauth_callback(auth_hash)

# Test adapter
adapter = Slack::WorkspaceAdapter.new(workspace)
adapter.post_preview_announcement(channel_id: "C123", user_id: "U123")
```

---

## Quick Reference

### Flow Patterns

**OAuth Callback:**
```
Controller → Service → Model (transaction) → Workflow (if first install)
```

**Interactive Component:**
```
Controller → Service → Adapter → Client
```

**Workspace Setup:**
```
Workflow (orchestration) → Service (business logic) → Adapter (platform) → Client (API)
```

### When to Use What

| Need | Use |
|------|-----|
| Database operations | Model |
| HTTP handling | Controller |
| Business logic (reusable) | Service |
| Platform-specific code | Adapter |
| Multi-step async process | Workflow |
| Low-level API calls | Client |

### Architecture Layers

```
┌─────────────────────────────────────────┐
│           Controllers                   │  ← HTTP/Request handling
│         (Thin - delegate)               │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│            Services                     │  ← Business logic (platform-agnostic)
│      (Coordinate & orchestrate)         │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│            Adapters                     │  ← Platform-specific code
│   (Slack, Teams - translate)            │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│            Clients                      │  ← Low-level API wrappers
│       (HTTP, API calls)                 │
└─────────────────────────────────────────┘

         ┌──────────────┐
         │   Models     │  ← Domain logic & data
         └──────────────┘

         ┌──────────────┐
         │  Workflows   │  ← Async orchestration
         └──────────────┘
```

---

## Examples from Codebase

### Perfect Service Example

`app/services/slack_authentication_service.rb` - Coordinates OAuth, triggers workflow

### Perfect Adapter Example

`app/adapters/slack/workspace_adapter.rb` - Platform-specific operations

### Perfect Workflow Example

`app/workflows/slack_workspace_setup_workflow.rb` - Thin orchestration

### Perfect Controller Example

`app/controllers/auth/omniauth_callbacks_controller.rb` - Delegates to service

---

## Common Mistakes to Avoid

### ❌ Don't: Put business logic in controllers
```ruby
# Bad
def slack
  workspace = Workspace.find_or_create_from_slack!(auth_hash)
  if workspace.incidents_channel_id.blank?
    SlackWorkspaceSetupWorkflow.start!(workspace)
  end
  # ... more logic
end
```

### ✅ Do: Delegate to services
```ruby
# Good
def slack
  service = SlackAuthenticationService.new
  result = service.process_oauth_callback(auth_hash)
  session[:user_id] = result[:user].id
  redirect_to dashboard_path
end
```

### ❌ Don't: Call adapters directly from workflows
```ruby
# Bad
def create_channel(workflow:, step:, input:)
  adapter = Slack::WorkspaceAdapter.new(workflow.subject)
  adapter.create_incidents_channel
end
```

### ✅ Do: Use services
```ruby
# Good
def create_channel(workflow:, step:, input:)
  setup_service.create_incidents_channel(workflow.subject)
end
```

### ❌ Don't: Use string logging
```ruby
# Bad
Rails.logger.info "Created channel #{channel_id}"
```

### ✅ Do: Use structured JSON logging
```ruby
# Good
Rails.logger.info({
  event: "workspace_setup.channel_created",
  message: "Created incidents channel",
  channel_id: channel_id
})
```

---

*This guide reflects the current state of the FireFight codebase as of January 2026.*
