# FIR-26: Phase 1.5 — Incident Home Modal

## Overview

When `/ff` or `/firefight` is run without a subcommand, open an "Incident Home" modal — a searchable command hub with a dropdown of all available actions and dynamic help text that updates when an action is selected.

---

## Current State Audit

| Component | Status | Detail |
|---|---|---|
| `HomeHandler` — `home`/`nil` case | **Placeholder** | Returns ephemeral "Opening Incident Home..." text |
| `HomeHandler` architecture | **Class methods** | Uses `self.execute(command)` pattern, not instances |
| `Slack::ModalBuilder` — home modal | **Missing** | No `home_modal` method |
| `Slack::Client.open_modal` | **Done** | Exists |
| `Slack::Client.update_modal` | **Missing** | Not implemented; needed for dynamic help text |
| `InteractionsController` — `block_actions` | **Done** | Delegates to `SlackInteractionsService` |
| `SlackInteractionsService` — home action handler | **Missing** | No `select_action` handler |
| Test stubs | **Done** | `stub_open_modal` available |

---

## Architecture Decisions

### 1. HomeHandler Stays Class-Method Based

The ticket assumes instance methods (`@command`), but the HomeHandler was built with class methods in FIR-22 following the `ModalHandler` pattern. We'll keep class methods and pass `command` explicitly to internal helpers.

### 2. Add `update_modal` to Slack::Client

The home modal needs to dynamically update the help text when a user selects an action from the dropdown. This requires `views.update` API support.

### 3. Home Modal Opens via `Slack::ModalBuilder.home_modal`

Add the home modal to the existing `Slack::ModalBuilder` class rather than creating a new builder, keeping all modal definitions in one place.

---

## Implementation Steps

### Step 1: Add `Slack::Client.update_modal`

**File:** `app/adapters/slack/client.rb`

```ruby
# Update an existing modal in Slack
#
# @param workspace [Workspace] The workspace to use for authentication
# @param view_id [String] The ID of the view to update
# @param view [Hash] Updated Block Kit modal view JSON
# @return [Hash] Slack API response with indifferent access
# @raise [ApiError] if Slack API returns an error
def self.update_modal(workspace:, view_id:, view:)
  api_post(
    workspace: workspace,
    endpoint: "views.update",
    payload: {
      view_id: view_id,
      view: view
    }
  )
end
```

### Step 2: Add `stub_update_modal` to Test Helper

**File:** `test/support/slack_client_stub_helper.rb`

```ruby
def stub_update_modal(raises: nil)
  if raises
    Slack::Client.stubs(:update_modal).raises(raises)
  else
    Slack::Client.stubs(:update_modal).returns({ ok: true, view: { id: "V12345678" } })
  end
end
```

### Step 3: Add `home_modal` to ModalBuilder

**File:** `app/adapters/slack/modal_builder.rb`

Add class method `self.home_modal`:

```ruby
def self.home_modal
  {
    type: "modal",
    callback_id: "incident_home_modal",
    title: {
      type: "plain_text",
      text: "Incident Home"
    },
    close: {
      type: "plain_text",
      text: "Close"
    },
    blocks: [
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: "*I want to...*"
        }
      },
      {
        type: "input",
        dispatch_action: true,
        block_id: "action_select_block",
        element: {
          type: "static_select",
          action_id: "home_action_select",
          placeholder: {
            type: "plain_text",
            text: "Select an action"
          },
          options: home_modal_options
        },
        label: {
          type: "plain_text",
          text: "Choose an action"
        }
      },
      {
        type: "section",
        block_id: "command_details_block",
        text: {
          type: "mrkdwn",
          text: "_Select an action above to see how to use the command directly._"
        }
      }
    ]
  }
end

def self.home_modal_options
  [
    { text: { type: "plain_text", text: "Create a new incident" }, value: "new", description: { type: "plain_text", text: "/ff new" } },
    { text: { type: "plain_text", text: "Update incident summary" }, value: "summary", description: { type: "plain_text", text: "/ff summary" } },
    { text: { type: "plain_text", text: "Set incident lead" }, value: "lead", description: { type: "plain_text", text: "/ff lead" } },
    { text: { type: "plain_text", text: "Update status" }, value: "status", description: { type: "plain_text", text: "/ff status" } },
    { text: { type: "plain_text", text: "Change severity" }, value: "severity", description: { type: "plain_text", text: "/ff severity" } },
    { text: { type: "plain_text", text: "Escalate to someone" }, value: "escalate", description: { type: "plain_text", text: "/ff escalate" } },
    { text: { type: "plain_text", text: "Manage actions" }, value: "actions", description: { type: "plain_text", text: "/ff actions" } },
    { text: { type: "plain_text", text: "Close incident" }, value: "close", description: { type: "plain_text", text: "/ff close" } },
    { text: { type: "plain_text", text: "Generate postmortem" }, value: "postmortem", description: { type: "plain_text", text: "/ff postmortem" } },
    { text: { type: "plain_text", text: "View timeline" }, value: "timeline", description: { type: "plain_text", text: "/ff timeline" } },
    { text: { type: "plain_text", text: "List active incidents" }, value: "list", description: { type: "plain_text", text: "/ff list" } }
  ]
end
```

**Key:** The `dispatch_action: true` on the input block causes Slack to send a `block_actions` event when the user changes the selection, enabling dynamic help text.

### Step 4: Add `home_command_help` to ModalBuilder

**File:** `app/adapters/slack/modal_builder.rb`

```ruby
def self.home_command_help(command)
  case command
  when "new"
    "*Create a new incident*\n\nUsage: `/ff new`\nOpens the incident creation form."
  when "summary"
    "*Update incident summary*\n\nUsage: `/ff summary`\nUpdate the current understanding of the incident."
  when "lead"
    "*Set incident lead*\n\nUsage: `/ff lead`\nAssign an incident lead to coordinate response."
  when "status"
    "*Update status*\n\nUsage: `/ff status`\nChange the incident status (e.g., Investigating, Identified, Monitoring)."
  when "severity"
    "*Change severity*\n\nUsage: `/ff severity [critical|major|minor]`\nEscalate or de-escalate the incident severity."
  when "escalate"
    "*Escalate to someone*\n\nUsage: `/ff escalate`\nPage or notify someone about this incident."
  when "actions"
    "*Manage actions*\n\nUsage: `/ff actions`\nView, create, and complete incident action items."
  when "close"
    "*Close incident*\n\nUsage: `/ff close` or `/ff resolve`\nMark the incident as resolved."
  when "postmortem"
    "*Generate postmortem*\n\nUsage: `/ff postmortem`\nGenerate a postmortem document from the incident timeline."
  when "timeline"
    "*View timeline*\n\nUsage: `/ff timeline`\nSee the full history of incident events."
  when "list"
    "*List active incidents*\n\nUsage: `/ff list`\nShow all currently open incidents."
  else
    "_Select an action above to see how to use the command directly._"
  end
end
```

### Step 5: Update HomeHandler — Open Modal

**File:** `app/services/commands/firefight/home_handler.rb`

Replace the `when "home", nil` case:

```ruby
when "home", nil
  open_home_modal(command)
```

Add private class method:

```ruby
private_class_method def self.open_home_modal(command)
  workspace = command.workspace
  return ephemeral("Workspace not found. Please reinstall Firefight.") unless workspace

  modal = Slack::ModalBuilder.home_modal

  Slack::Client.open_modal(
    workspace: workspace,
    trigger_id: command.trigger_id,
    view: modal
  )

  Rails.logger.info({
    event: "incident_home.opened",
    workspace_id: workspace.id,
    user_id: command.user_id
  })

  { ok: true }
rescue Slack::Client::TriggerExpiredError
  ephemeral("This command has expired. Please try `/ff` again.")
end
```

### Step 6: Add `home_action_select` Handler to SlackInteractionsService

**File:** `app/services/slack_interactions_service.rb`

```ruby
def handle_home_action_select(payload)
  workspace = find_workspace(payload)
  action = payload.dig("actions", 0)
  selected_value = action.dig("selected_option", "value")
  view = payload["view"]
  view_id = view["id"]

  help_text = Slack::ModalBuilder.home_command_help(selected_value)

  # Rebuild blocks with updated help text
  updated_blocks = view["blocks"].map do |block|
    if block["block_id"] == "command_details_block"
      block.merge("text" => { "type" => "mrkdwn", "text" => help_text })
    else
      block
    end
  end

  Slack::Client.update_modal(
    workspace: workspace,
    view_id: view_id,
    view: {
      type: "modal",
      callback_id: "incident_home_modal",
      title: view["title"],
      close: view["close"],
      blocks: updated_blocks
    }
  )

  nil
rescue => e
  Rails.logger.error({
    event: "incident_home.update_error",
    error: e.message
  })
  nil
end
```

### Step 7: Wire `home_action_select` in InteractionsController

**File:** `app/controllers/api/v1/interactions_controller.rb`

Add case to `handle_block_actions`:

```ruby
when "home_action_select"
  service.handle_home_action_select(payload)
  head :ok
```

### Step 8: Write Tests

#### 8a. HomeHandler tests — modal opening

**File:** `test/services/commands/firefight/home_handler_test.rb` (update existing)

Replace the existing "handles empty command as home" test:

```ruby
test "opens home modal for empty command" do
  stub_open_modal
  command = build_command("")
  response = Commands::Firefight::HomeHandler.execute(command)
  assert response[:ok]
end

test "opens home modal for 'home' subcommand" do
  stub_open_modal
  command = build_command("home")
  response = Commands::Firefight::HomeHandler.execute(command)
  assert response[:ok]
end

test "handles trigger expiration for home modal" do
  stub_open_modal(raises: Slack::Client::TriggerExpiredError)
  command = build_command("")
  response = Commands::Firefight::HomeHandler.execute(command)
  assert_equal "ephemeral", response[:response_type]
  assert_includes response[:text], "expired"
end
```

#### 8b. ModalBuilder tests

**File:** `test/adapters/slack/modal_builder_test.rb` (create if needed)

```ruby
test "home_modal returns valid Block Kit structure" do
  modal = Slack::ModalBuilder.home_modal
  assert_equal "modal", modal[:type]
  assert_equal "incident_home_modal", modal[:callback_id]
  assert modal[:blocks].any? { |b| b[:block_id] == "action_select_block" }
end

test "home_command_help returns text for known commands" do
  %w[new summary lead status severity escalate actions close postmortem timeline list].each do |cmd|
    text = Slack::ModalBuilder.home_command_help(cmd)
    assert_includes text, "/ff"
  end
end
```

#### 8c. SlackInteractionsService — action select tests

**File:** `test/services/slack_interactions_service_test.rb` (append)

```ruby
test "handle_home_action_select updates modal with help text" do
  stub_update_modal

  payload = {
    "type" => "block_actions",
    "team" => { "id" => @workspace.platform_id },
    "view" => {
      "id" => "V123",
      "title" => { "type" => "plain_text", "text" => "Incident Home" },
      "close" => { "type" => "plain_text", "text" => "Close" },
      "blocks" => [
        { "type" => "section", "text" => { "type" => "mrkdwn", "text" => "*I want to...*" } },
        { "block_id" => "action_select_block", "type" => "input" },
        { "block_id" => "command_details_block", "type" => "section", "text" => { "type" => "mrkdwn", "text" => "placeholder" } }
      ]
    },
    "actions" => [{
      "action_id" => "home_action_select",
      "selected_option" => { "value" => "new" }
    }]
  }

  result = @service.handle_home_action_select(payload)
  assert_nil result
end
```

---

## File Summary

| Action | File | Description |
|---|---|---|
| **Edit** | `app/adapters/slack/client.rb` | Add `update_modal` method |
| **Edit** | `app/adapters/slack/modal_builder.rb` | Add `home_modal`, `home_modal_options`, `home_command_help` |
| **Edit** | `app/services/commands/firefight/home_handler.rb` | Replace placeholder with modal opening |
| **Edit** | `app/services/slack_interactions_service.rb` | Add `handle_home_action_select` |
| **Edit** | `app/controllers/api/v1/interactions_controller.rb` | Add `home_action_select` routing |
| **Edit** | `test/support/slack_client_stub_helper.rb` | Add `stub_update_modal` |
| **Edit** | `test/services/commands/firefight/home_handler_test.rb` | Update home tests for modal |
| **Edit** | `test/services/slack_interactions_service_test.rb` | Add action select tests |
| **Create** | `test/adapters/slack/modal_builder_test.rb` | ModalBuilder unit tests |

## Dependencies

- **FIR-22** must be complete (HomeHandler exists with subcommand routing) — **Done**
- `Slack::Client.open_modal` — **Done**
- `InteractionsController` handles `block_actions` — **Done**
