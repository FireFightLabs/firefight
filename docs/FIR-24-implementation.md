# FIR-24: Phase 1.3 — Global Shortcut: Create Incident

## Overview

Register a "Create an incident" global Slack shortcut and handle it via the existing interactions pipeline. The shortcut opens the same incident creation modal used by `/ff new`.

---

## Current State Audit

| Component | Status | Detail |
|---|---|---|
| Slack manifests — `shortcuts:` section | **Missing** | No shortcuts in any manifest |
| `InteractionsController` — `shortcut` type routing | **Missing** | Handles `view_submission`, `block_actions`, `view_closed` but not `shortcut` |
| `SlackInteractionsService` — shortcut handler | **Missing** | No shortcut-related methods |
| `Slack::ModalBuilder.incident_creation_form` | **Done** | Existing modal with name, severity, summary fields |
| `Slack::Client.open_modal` | **Done** | Works, raises `TriggerExpiredError` |
| `WorkspaceMembership` model | **Done** | Has `platform_user_id` for Slack user lookup |
| `SlackClientStubHelper` — `stub_open_modal` | **Done** | Test helper available |

---

## Architecture Decision

**Reuse the existing `Slack::ModalBuilder.incident_creation_form`** rather than creating a new `Slack::IncidentModalBuilder`. The ticket proposes a new builder class with slightly different fields (adds visibility/privacy selector), but the existing builder already works and is referenced by the `/ff new` flow via `Commands::ModalHandler`. We should extend the existing builder with the visibility field rather than create a parallel class.

**Handle shortcuts in the service layer** via `SlackInteractionsService`, not a separate `Slack::Shortcuts::CreateIncidentHandler` class. This follows the existing pattern where the controller delegates to the service, keeping the controller thin.

---

## Implementation Steps

### Step 1: Update Slack Manifests — Add Shortcuts

**Files:** `config/slack_manifests/{development,staging,production}.yml`

Add a `shortcuts:` section under `features:`:

```yaml
features:
  bot_user:
    ...
  slash_commands:
    ...
  shortcuts:
    - name: "Create an incident"
      type: global
      callback_id: create_incident_shortcut
      description: "Quickly declare a new incident"
```

All three manifests need this addition.

### Step 2: Add Visibility Field to Existing Modal Builder

**File:** `app/adapters/slack/modal_builder.rb`

Add a third block to `incident_creation_form` after the summary block:

```ruby
{
  type: "input",
  block_id: "visibility_block",
  element: {
    type: "static_select",
    action_id: "visibility_select",
    options: [
      {
        text: { type: "plain_text", text: "Everyone (public)" },
        value: "public"
      },
      {
        text: { type: "plain_text", text: "Private" },
        value: "private"
      }
    ],
    initial_option: {
      text: { type: "plain_text", text: "Everyone (public)" },
      value: "public"
    }
  },
  label: {
    type: "plain_text",
    text: "Who should be able to see this incident?"
  },
  hint: {
    type: "plain_text",
    text: "Public incidents are visible to everyone in the workspace. Private incidents are only accessible to invited members."
  }
}
```

### Step 3: Add Shortcut Routing to InteractionsController

**File:** `app/controllers/api/v1/interactions_controller.rb`

Add `"shortcut"` case to the `create` method's `case` statement:

```ruby
when "shortcut"
  handle_shortcut(payload)
```

Add private method:

```ruby
def handle_shortcut(payload)
  callback_id = payload["callback_id"]
  service = SlackInteractionsService.new

  case callback_id
  when "create_incident_shortcut"
    result = service.handle_create_incident_shortcut(payload)
    if result
      render json: result
    else
      head :ok
    end
  else
    Rails.logger.warn({
      event: "interactions.unknown_shortcut",
      callback_id: callback_id
    })
    head :ok
  end
end
```

### Step 4: Add Shortcut Handler to SlackInteractionsService

**File:** `app/services/slack_interactions_service.rb`

Add method:

```ruby
def handle_create_incident_shortcut(payload)
  workspace = find_workspace(payload)
  trigger_id = payload["trigger_id"]

  modal = Slack::ModalBuilder.incident_creation_form

  Slack::Client.open_modal(
    workspace: workspace,
    trigger_id: trigger_id,
    view: modal
  )

  Rails.logger.info({
    event: "shortcut.create_incident",
    message: "Create incident shortcut triggered",
    workspace_id: workspace.id,
    user_id: payload.dig("user", "id")
  })

  nil # Modal opened successfully, no response body needed
rescue Slack::Client::TriggerExpiredError
  Rails.logger.warn({
    event: "shortcut.trigger_expired",
    workspace_id: workspace&.id,
    trigger_id: trigger_id
  })

  {
    response_action: "errors",
    errors: { base: "This shortcut has expired. Please try again." }
  }
end
```

### Step 5: Write Tests

#### 5a. InteractionsController — shortcut tests

**File:** `test/controllers/api/v1/interactions_controller_test.rb` (append)

```ruby
# --- Shortcut Tests ---

test "handles create_incident_shortcut" do
  stub_open_modal

  payload = {
    type: "shortcut",
    callback_id: "create_incident_shortcut",
    trigger_id: "12345.trigger",
    user: { id: "U12345678" },
    team: { id: @workspace.platform_id }
  }

  request_data = slack_interaction_request(payload)
  post api_v1_interactions_url,
       params: request_data[:body],
       headers: request_data[:headers]

  assert_response :ok
end

test "handles unknown shortcut gracefully" do
  payload = {
    type: "shortcut",
    callback_id: "unknown_shortcut",
    trigger_id: "12345.trigger",
    user: { id: "U12345678" },
    team: { id: @workspace.platform_id }
  }

  request_data = slack_interaction_request(payload)
  post api_v1_interactions_url,
       params: request_data[:body],
       headers: request_data[:headers]

  assert_response :ok
end
```

#### 5b. SlackInteractionsService — shortcut tests

**File:** `test/services/slack_interactions_service_test.rb` (append)

```ruby
# --- Shortcut Tests ---

test "handle_create_incident_shortcut opens modal" do
  stub_open_modal

  payload = {
    "type" => "shortcut",
    "callback_id" => "create_incident_shortcut",
    "trigger_id" => "12345.trigger",
    "user" => { "id" => "U12345678" },
    "team" => { "id" => @workspace.platform_id }
  }

  result = @service.handle_create_incident_shortcut(payload)
  assert_nil result # nil means modal opened, no error
end

test "handle_create_incident_shortcut handles trigger expiration" do
  stub_open_modal(raises: Slack::Client::TriggerExpiredError)

  payload = {
    "type" => "shortcut",
    "callback_id" => "create_incident_shortcut",
    "trigger_id" => "expired.trigger",
    "user" => { "id" => "U12345678" },
    "team" => { "id" => @workspace.platform_id }
  }

  result = @service.handle_create_incident_shortcut(payload)
  assert_equal "errors", result[:response_action]
  assert_includes result[:errors][:base], "expired"
end
```

---

## File Summary

| Action | File | Description |
|---|---|---|
| **Edit** | `config/slack_manifests/development.yml` | Add `shortcuts:` section |
| **Edit** | `config/slack_manifests/staging.yml` | Add `shortcuts:` section |
| **Edit** | `config/slack_manifests/production.yml` | Add `shortcuts:` section |
| **Edit** | `app/adapters/slack/modal_builder.rb` | Add visibility field to creation form |
| **Edit** | `app/controllers/api/v1/interactions_controller.rb` | Add `shortcut` type routing |
| **Edit** | `app/services/slack_interactions_service.rb` | Add `handle_create_incident_shortcut` |
| **Edit** | `test/controllers/api/v1/interactions_controller_test.rb` | Add shortcut controller tests |
| **Edit** | `test/services/slack_interactions_service_test.rb` | Add shortcut service tests |

## Acceptance Criteria Mapping

| Criteria | Covered By |
|---|---|
| "Create an incident" shortcut registered in manifest | Step 1 |
| Shortcut appears in Slack shortcuts menu | Step 1 (manifest registration) |
| Shortcut works from any channel, DM, or context | Global shortcut type in manifest |
| Opens incident creation modal with correct fields | Step 2 + Step 4 |
| Handles workspace/user not found errors | Step 4 (via `find_workspace` which raises `RecordNotFound`) |
| Handles trigger expiration gracefully | Step 4 rescue block |
| Logs shortcut usage with structured JSON | Step 4 logging |
| All tests pass | Step 5 |
| Shortcut callback_id is unique and descriptive | `create_incident_shortcut` |
