# FIR-22: Phase 1.2 — Slash Command Infrastructure

## Overview

Set up subcommand routing infrastructure for `/firefight` and `/ff` slash commands. The external plumbing (manifests, controller, job, adapter, signature verification) already exists. This ticket delivers the **internal routing layer**: a command-name-aware dispatcher and a `HomeHandler` that routes subcommands to future phase handlers.

---

## Current State Audit

| Component | File | Status |
|---|---|---|
| Slack manifests (`/firefight`, `/ff`) | `config/slack_manifests/{dev,staging,prod}.yml` | Done |
| Routes `POST /api/v1/commands` | `config/routes.rb:13` | Done |
| `Api::V1::CommandsController` | `app/controllers/api/v1/commands_controller.rb` | Done |
| Signature verification | `app/adapters/slack/signature_verifier.rb` | Done |
| `ProcessCommandJob` | `app/jobs/process_command_job.rb` | Done |
| `Slack::CommandAdapter` | `app/adapters/slack/command_adapter.rb` | Done — stores `/firefight` or `/ff` in `metadata[:command]` |
| `Command` PORO | `app/models/command.rb` | Done — has `subcommand`, `args`, `blank?` |
| `CommandDispatcher` | `app/services/command_dispatcher.rb` | **Needs update** — routes by subcommand text only, not by slash command name |
| `Commands::Firefight::HomeHandler` | — | **Missing** — core deliverable |
| `CommandDispatcher` tests | — | **Missing** — no test file exists |
| `HomeHandler` tests | — | **Missing** |

### Existing Command Flow

```
Slack POST /api/v1/commands
  → CommandsController#create (signature verified, workspace found)
    → ProcessCommandJob.perform_later("slack", payload)
      → Slack::CommandAdapter.parse(payload) → Command PORO
        → CommandDispatcher.dispatch(command)
          → handler.execute(command)
```

The adapter already stores the slash command name in `command.metadata[:command]` (e.g., `"/firefight"` or `"/ff"`), but the dispatcher ignores it — it only looks at `command.subcommand` (first word of text). The dispatcher also references `HelpHandler`, `StatusHandler`, `ListHandler` that **do not exist as files**.

---

## Architecture Decision

**Route by slash command name first, then subcommand internally.**

The dispatcher will check `command.metadata[:command]` to identify `/firefight` or `/ff`, then delegate to `HomeHandler`. The `HomeHandler` reads `command.subcommand` to route to the correct phase handler.

This keeps the dispatcher extensible (other slash commands could be added later) while giving the firefight command family its own self-contained router.

---

## Implementation Steps

### Step 1: Add `Command#command_name` helper

**File:** `app/models/command.rb`

Add a method to extract the clean command name from metadata:

```ruby
# Get slash command name without leading "/"
# e.g., "/firefight" → "firefight", "/ff" → "ff"
def command_name
  metadata[:command]&.to_s&.delete_prefix("/")
end
```

**Why:** Gives the dispatcher a clean, platform-agnostic way to check which slash command was invoked without reaching into metadata internals.

---

### Step 2: Update `CommandDispatcher`

**File:** `app/services/command_dispatcher.rb`

Replace the current subcommand-based routing with command-name-aware routing:

```ruby
class CommandDispatcher
  class UnknownCommandError < StandardError; end

  COMMAND_HANDLERS = {
    "firefight" => Commands::Firefight::HomeHandler,
    "ff" => Commands::Firefight::HomeHandler
  }.freeze

  def self.find(command)
    # Route by slash command name (e.g., /firefight, /ff)
    handler = COMMAND_HANDLERS[command.command_name]
    return handler if handler

    # Fallback: open modal for unrecognized commands
    Commands::ModalHandler
  end

  def self.dispatch(command)
    handler = find(command)
    handler.execute(command)
  end
end
```

**Changes from current:**
- Adds `COMMAND_HANDLERS` constant keyed by command name (not subcommand text)
- Removes dead references to non-existent `HelpHandler`, `StatusHandler`, `ListHandler`
- Keeps `Commands::ModalHandler` as the fallback
- `find` + `dispatch` API unchanged

---

### Step 3: Create `Commands::Firefight::HomeHandler`

**File:** `app/services/commands/firefight/home_handler.rb`

```ruby
module Commands
  module Firefight
    class HomeHandler
      SUBCOMMANDS = %w[
        new home summary lead status severity
        escalate action actions close resolve
        postmortem timeline list
      ].freeze

      def self.execute(command)
        subcommand = command.subcommand&.downcase

        case subcommand
        when "new"
          # Phase 1.3: NewHandler — opens incident creation modal
          Commands::ModalHandler.execute(command)
        when "home", nil
          # Phase 1.5: Incident Home modal
          ephemeral("Opening Incident Home...")
        when "summary"
          # Phase 2.1
          ephemeral("Summary command coming soon...")
        when "lead"
          # Phase 2.2
          ephemeral("Lead command coming soon...")
        when "status"
          # Phase 3.1
          ephemeral("Status command coming soon...")
        when "severity"
          # Phase 3.2
          ephemeral("Severity command coming soon...")
        when "escalate"
          # Phase 4.5
          ephemeral("Escalate command coming soon...")
        when "action", "actions"
          # Phase 4.1
          ephemeral("Actions command coming soon...")
        when "close", "resolve"
          # Phase 5.1
          ephemeral("Close command coming soon...")
        when "postmortem"
          # Phase 5.2
          ephemeral("Postmortem command coming soon...")
        when "timeline"
          # Phase 6.1
          ephemeral("Timeline command coming soon...")
        when "list"
          # Phase 6.2
          ephemeral("List command coming soon...")
        else
          ephemeral("Unknown subcommand: `#{subcommand}`. Type `/ff` for available commands.")
        end
      rescue => e
        Rails.logger.error({
          event: "firefight.command_error",
          command: command.text,
          subcommand: subcommand,
          error: e.message,
          backtrace: e.backtrace&.first(5)
        }.to_json)

        ephemeral("Sorry, something went wrong. Please try again.")
      end

      private_class_method def self.ephemeral(text)
        { response_type: "ephemeral", text: text }
      end
    end
  end
end
```

**Design notes:**
- Follows existing pattern: class method `self.execute(command)` matching `ModalHandler`
- `"new"` delegates to existing `ModalHandler` (incident creation modal) — preserves current behavior
- Empty command (`/ff` with no args) routes to future Incident Home
- Aliases supported: `action`/`actions`, `close`/`resolve`
- Structured JSON error logging matches codebase conventions
- `ephemeral` helper reduces repetition

---

### Step 4: Update Slack Manifests — `usage_hint`

**Files:** `config/slack_manifests/{development,staging,production}.yml`

Update the `usage_hint` to reflect available subcommands:

```yaml
slash_commands:
  - command: /firefight
    url: ...
    description: "Manage incidents and coordinate response"
    usage_hint: "[new|summary|lead|status|actions|close|timeline|list]"
  - command: /ff
    url: ...
    description: "Manage incidents (short alias for /firefight)"
    usage_hint: "[new|summary|lead|status|actions|close|timeline|list]"
```

**Changes:**
- `description` updated to be more descriptive
- `usage_hint` updated from `"[subcommand]"` to list actual subcommands

---

### Step 5: Write Tests

#### 5a. `CommandDispatcher` tests

**File:** `test/services/command_dispatcher_test.rb`

```ruby
require "test_helper"

class CommandDispatcherTest < ActiveSupport::TestCase
  test "routes /firefight to Firefight::HomeHandler" do
    command = build_command(command_name: "/firefight", text: "new")
    assert_equal Commands::Firefight::HomeHandler, CommandDispatcher.find(command)
  end

  test "routes /ff to Firefight::HomeHandler" do
    command = build_command(command_name: "/ff", text: "status")
    assert_equal Commands::Firefight::HomeHandler, CommandDispatcher.find(command)
  end

  test "falls back to ModalHandler for unknown slash commands" do
    command = build_command(command_name: "/unknown", text: "")
    assert_equal Commands::ModalHandler, CommandDispatcher.find(command)
  end

  test "falls back to ModalHandler when no command name" do
    command = build_command(command_name: nil, text: "")
    assert_equal Commands::ModalHandler, CommandDispatcher.find(command)
  end

  private

  def build_command(command_name:, text:)
    Command.new(
      platform: Platforms::SLACK,
      workspace_id: SecureRandom.uuid,
      user_id: "U12345678",
      text: text,
      channel_id: "C12345678",
      metadata: { command: command_name }
    )
  end
end
```

#### 5b. `HomeHandler` tests

**File:** `test/services/commands/firefight/home_handler_test.rb`

```ruby
require "test_helper"

class Commands::Firefight::HomeHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  # --- Subcommand routing ---

  test "routes 'new' subcommand to ModalHandler" do
    command = build_command("new")

    # Verify ModalHandler.execute is called
    modal_called = false
    Commands::ModalHandler.stub(:execute, ->(_cmd) { modal_called = true }) do
      Commands::Firefight::HomeHandler.execute(command)
    end

    assert modal_called
  end

  test "handles empty command (home)" do
    command = build_command("")
    response = Commands::Firefight::HomeHandler.execute(command)

    assert_equal "ephemeral", response[:response_type]
    assert_includes response[:text], "Incident Home"
  end

  test "handles nil text (home)" do
    command = build_command(nil)
    response = Commands::Firefight::HomeHandler.execute(command)

    assert_equal "ephemeral", response[:response_type]
    assert_includes response[:text], "Incident Home"
  end

  # --- Placeholder subcommands ---

  %w[summary lead status severity escalate timeline list postmortem].each do |sub|
    test "handles '#{sub}' subcommand with placeholder" do
      command = build_command(sub)
      response = Commands::Firefight::HomeHandler.execute(command)

      assert_equal "ephemeral", response[:response_type]
      assert_includes response[:text], "coming soon"
    end
  end

  # --- Aliases ---

  test "handles 'action' alias for 'actions'" do
    command = build_command("action")
    response = Commands::Firefight::HomeHandler.execute(command)

    assert_equal "ephemeral", response[:response_type]
    assert_includes response[:text], "Actions"
  end

  test "handles 'resolve' alias for 'close'" do
    command = build_command("resolve")
    response = Commands::Firefight::HomeHandler.execute(command)

    assert_equal "ephemeral", response[:response_type]
    assert_includes response[:text], "Close"
  end

  # --- Unknown subcommand ---

  test "returns error for unknown subcommand" do
    command = build_command("notacommand")
    response = Commands::Firefight::HomeHandler.execute(command)

    assert_equal "ephemeral", response[:response_type]
    assert_includes response[:text], "Unknown subcommand"
    assert_includes response[:text], "notacommand"
  end

  # --- Case insensitivity ---

  test "handles uppercase subcommands" do
    command = build_command("NEW")
    # Should not raise or return unknown
    modal_called = false
    Commands::ModalHandler.stub(:execute, ->(_cmd) { modal_called = true }) do
      Commands::Firefight::HomeHandler.execute(command)
    end

    assert modal_called
  end

  # --- Error handling ---

  test "returns error message when handler raises" do
    command = build_command("new")
    Commands::ModalHandler.stub(:execute, ->(_cmd) { raise "boom" }) do
      response = Commands::Firefight::HomeHandler.execute(command)

      assert_equal "ephemeral", response[:response_type]
      assert_includes response[:text], "something went wrong"
    end
  end

  # --- Subcommand with extra args ---

  test "routes correctly when subcommand has additional arguments" do
    command = build_command("new production database down")
    modal_called = false
    Commands::ModalHandler.stub(:execute, ->(_cmd) { modal_called = true }) do
      Commands::Firefight::HomeHandler.execute(command)
    end

    assert modal_called
  end

  private

  def build_command(text)
    Command.new(
      platform: Platforms::SLACK,
      workspace_id: @workspace.id,
      user_id: "U12345678",
      text: text.to_s,
      trigger_id: "123456.789.abc123",
      channel_id: "C12345678",
      metadata: { command: "/ff" }
    )
  end
end
```

---

## File Summary

| Action | File | Description |
|---|---|---|
| **Edit** | `app/models/command.rb` | Add `command_name` method |
| **Edit** | `app/services/command_dispatcher.rb` | Route by slash command name via `COMMAND_HANDLERS` |
| **Create** | `app/services/commands/firefight/home_handler.rb` | Subcommand router with placeholders |
| **Edit** | `config/slack_manifests/development.yml` | Update `description` and `usage_hint` |
| **Edit** | `config/slack_manifests/staging.yml` | Update `description` and `usage_hint` |
| **Edit** | `config/slack_manifests/production.yml` | Update `description` and `usage_hint` |
| **Create** | `test/services/command_dispatcher_test.rb` | Dispatcher routing tests |
| **Create** | `test/services/commands/firefight/home_handler_test.rb` | HomeHandler tests |

## Acceptance Criteria Mapping

| Criteria | Covered By |
|---|---|
| `/firefight` registered in Slack manifest | Already done (all 3 envs) |
| `/ff` registered as alias | Already done (all 3 envs) |
| CommandDispatcher routes both to HomeHandler | Step 2 + Step 5a |
| HomeHandler parses subcommands correctly | Step 3 + Step 5b |
| Unknown subcommands return helpful error | Step 3 `else` branch + test |
| All tests pass | Step 5 + Step 6 |
| Commands enqueue ProcessCommandJob correctly | Already done (existing controller + job) |
| Signature verification works for new commands | Already done (BaseController `before_action`) |
| Structured JSON logging for command events | Step 3 rescue block |

## Dependencies (all satisfied)

- `CommandDispatcher` — exists at `app/services/command_dispatcher.rb`
- `ProcessCommandJob` — exists at `app/jobs/process_command_job.rb`
- `Slack::CommandAdapter` — exists at `app/adapters/slack/command_adapter.rb`
- `Command` PORO — exists at `app/models/command.rb`

## Implementation Order

1. `Command#command_name` (no dependencies)
2. `Commands::Firefight::HomeHandler` (depends on Command)
3. `CommandDispatcher` update (depends on HomeHandler)
4. Manifest updates (independent)
5. Tests (depends on steps 1-3)
6. Run full test suite
