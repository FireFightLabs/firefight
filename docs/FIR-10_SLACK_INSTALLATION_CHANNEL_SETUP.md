# FIR-10: Slack App Installation - Auto-create #incidents Channel

## Overview

Automatically create and configure a shared `#incidents` channel when a workspace installs the FireFight Slack app, complete with a welcome message, share functionality, and preview announcement feature.

## User Story

**As a** Slack workspace admin installing FireFight
**I want** the app to automatically set up an #incidents channel with clear onboarding
**So that** my team knows where incidents are managed and how to get started

---

## Implementation Plan

### Phase 1: Database & Configuration

#### 1.1 Database Migration

Create migration to add `incidents_channel_id` to workspaces table:

```ruby
# db/migrate/YYYYMMDDHHMMSS_add_incidents_channel_to_workspaces.rb
class AddIncidentsChannelToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :incidents_channel_id, :string
    add_index :workspaces, :incidents_channel_id
  end
end
```

**Note:** No validation needed on `incidents_channel_id` since it's set asynchronously by the workflow.

#### 1.2 Slack Manifest Update

Update `config/slack_manifests/development.yml`, `staging.yml`, and `production.yml`:

The required scopes have already been added with inline comments:

```yaml
bot:
  - team:read          # Get workspace info (name, domain) during installation
  - commands           # Enable slash commands (/firefight, /ff)
  - chat:write         # Post messages to channels (welcome, incident announcements)
  - channels:manage    # Create #incidents channel on installation (FIR-10)
  - channels:join      # Bot can join channels it creates
  - channels:read      # Read channel info (check if #incidents exists)
  - users:read         # Get user info for @mentions in messages
```

**Action Required:** After updating manifest, push to Slack and reinstall app in test workspace:
```bash
bin/rails slack:manifest:push[development]
```

---

### Phase 2: Workspace Adapter Factory

Create a factory class that automatically instantiates the correct adapter based on platform.

**File:** `app/adapters/workspace_adapter.rb`

```ruby
class WorkspaceAdapter
  class UnsupportedPlatformError < StandardError; end

  # Factory method to create appropriate adapter based on workspace platform
  #
  # @param workspace [Workspace] The workspace record
  # @return [Slack::WorkspaceAdapter, Teams::WorkspaceAdapter] Platform-specific adapter
  # @raise [UnsupportedPlatformError] if platform is not supported
  def self.for(workspace)
    case workspace.platform
    when Platforms::SLACK
      Slack::WorkspaceAdapter.new(workspace)
    when Platforms::TEAMS
      Teams::WorkspaceAdapter.new(workspace)
    else
      raise UnsupportedPlatformError, "Unsupported platform: #{workspace.platform}"
    end
  end
end
```

**Usage:**
```ruby
# In workflows, controllers, jobs, etc.
adapter = WorkspaceAdapter.for(workspace)
adapter.create_incidents_channel
```

---

### Phase 3: Slack Workspace Adapter

Create a high-level adapter for workspace setup operations.

**File:** `app/adapters/slack/workspace_adapter.rb`

```ruby
module Slack
  class WorkspaceAdapter
    CHANNEL_DESCRIPTION = "FireFight announcements channel. Every time someone declares an incident, we'll announce it here, and make sure the post is always up to date."

    def initialize(workspace)
      @workspace = workspace
    end

    # Create incidents channel
    #
    # @return [Hash] Normalized response with :channel_id, :channel_name, :already_existed
    def create_incidents_channel
      result = Slack::Client.create_channel(
        workspace: @workspace,
        name: "incidents",
        is_private: false
      )

      {
        channel_id: result[:channel][:id],
        channel_name: result[:channel][:name],
        already_existed: false
      }
    rescue Slack::Client::ChannelExistsError => e
      Rails.logger.warn({
        event: "slack.workspace_adapter.channel_already_exists",
        message: "Incidents channel already exists, will use existing",
        workspace_id: @workspace.id,
        error: e.message
      })

      existing = find_existing_channel("incidents")

      {
        channel_id: existing[:id],
        channel_name: existing[:name],
        already_existed: true
      }
    end

    # Set channel topic and purpose (description)
    #
    # @param channel_id [String] Slack channel ID
    def set_channel_metadata(channel_id:)
      Slack::Client.set_channel_topic(
        workspace: @workspace,
        channel: channel_id,
        topic: CHANNEL_DESCRIPTION
      )

      Slack::Client.set_channel_purpose(
        workspace: @workspace,
        channel: channel_id,
        purpose: CHANNEL_DESCRIPTION
      )

      { success: true }
    end

    # Invite user to channel
    #
    # @param channel_id [String] Slack channel ID
    # @param user_id [String] Slack user ID
    def invite_user(channel_id:, user_id:)
      Slack::Client.invite_to_channel(
        workspace: @workspace,
        channel: channel_id,
        users: user_id
      )

      { invited_user: user_id }
    end

    # Post welcome message with interactive buttons
    #
    # @param channel_id [String] Slack channel ID
    # @return [Hash] Response with :message_ts
    def post_welcome_message(channel_id:)
      blocks = Slack::InstallationMessageBuilder.welcome_message_blocks

      result = Slack::Client.post_message(
        workspace: @workspace,
        channel: channel_id,
        text: "Welcome to FireFight!",
        blocks: blocks[:blocks]
      )

      { message_ts: result[:ts] }
    end

    private

    def find_existing_channel(name)
      channels = Slack::Client.list_conversations(workspace: @workspace)
      channel = channels.find { |ch| ch[:name] == name }

      raise Slack::Client::ChannelNotFoundError, "Channel '#{name}' not found" unless channel

      channel
    end
  end
end
```

---

### Phase 4: Installation Message Builder

Create Block Kit message builders for welcome, preview, and share functionality.

**File:** `app/adapters/slack/installation_message_builder.rb`

```ruby
module Slack
  class InstallationMessageBuilder
    # Welcome message posted to #incidents channel
    def self.welcome_message_blocks
      {
        blocks: [
          {
            type: "header",
            text: {
              type: "plain_text",
              text: "Welcome to FireFight!",
              emoji: true
            }
          },
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "*This is your central incident hub.*\n\nWhen an incident is declared, we'll spin up a dedicated response channel and post an announcement here. Each announcement stays current as the incident evolves, giving you real-time visibility across all ongoing incidents in your organization."
            }
          },
          {
            type: "actions",
            elements: [
              {
                type: "button",
                text: {
                  type: "plain_text",
                  text: "🔗 Share this channel",
                  emoji: true
                },
                action_id: "share_incidents_channel",
                style: "primary"
              },
              {
                type: "button",
                text: {
                  type: "plain_text",
                  text: "📢 Preview an announcement",
                  emoji: true
                },
                action_id: "preview_announcement"
              }
            ]
          }
        ]
      }
    end

    # Ephemeral preview message (only visible to clicking user)
    def self.preview_announcement_blocks(user_id)
      {
        blocks: [
          {
            type: "context",
            elements: [
              {
                type: "mrkdwn",
                text: "_Only visible to you_"
              }
            ]
          },
          {
            type: "header",
            text: {
              type: "plain_text",
              text: "[PREVIEW] Website is down",
              emoji: true
            }
          },
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "The marketing website is down: I'm getting a '502 Gateway OverallTimeout' error"
            }
          },
          {
            type: "section",
            fields: [
              {
                type: "mrkdwn",
                text: "🔥 *Severity:* Minor"
              },
              {
                type: "mrkdwn",
                text: "📊 *Status:* Investigating"
              },
              {
                type: "mrkdwn",
                text: "👤 *Reporter:* <@#{user_id}>"
              },
              {
                type: "mrkdwn",
                text: "👑 *Incident Lead:* <@#{user_id}>"
              }
            ]
          },
          {
            type: "actions",
            elements: [
              {
                type: "button",
                text: {
                  type: "plain_text",
                  text: "🌐 Incident homepage",
                  emoji: true
                },
                action_id: "preview_homepage_disabled",
                style: "primary"
              },
              {
                type: "button",
                text: {
                  type: "plain_text",
                  text: "📌 Subscribe",
                  emoji: true
                },
                action_id: "preview_subscribe_disabled"
              }
            ]
          }
        ]
      }
    end

    # Share channel modal
    def self.share_channel_modal(user_id, channel_id)
      {
        type: "modal",
        callback_id: "share_incidents_channel_modal",
        title: {
          type: "plain_text",
          text: "Share this channel"
        },
        submit: {
          type: "plain_text",
          text: "Share"
        },
        close: {
          type: "plain_text",
          text: "Cancel"
        },
        blocks: [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "👋 <@#{user_id}> is using FireFight in your Slack workspace\n\nFireFight helps your team manage incidents with better coordination and full visibility into what's happening.\n\nJoin the <##{channel_id}> channel to stay informed about active incidents, or explore the commands to see how FireFight can help during outages."
            }
          },
          {
            type: "input",
            block_id: "share_target_block",
            element: {
              type: "multi_conversations_select",
              action_id: "share_target_select",
              placeholder: {
                type: "plain_text",
                text: "Select channels or people"
              }
            },
            label: {
              type: "plain_text",
              text: "Where should we share this?"
            }
          },
          {
            type: "actions",
            elements: [
              {
                type: "button",
                text: {
                  type: "plain_text",
                  text: "Join the channel",
                  emoji: true
                },
                action_id: "join_incidents_channel",
                url: "slack://channel?id=#{channel_id}",
                style: "primary"
              }
            ]
          }
        ]
      }
    end

    # Message sent when sharing the channel
    def self.share_message(sharing_user_id, channel_id)
      {
        blocks: [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "👋 <@#{sharing_user_id}> is using FireFight in your Slack workspace\n\nFireFight helps your team manage incidents with better coordination and full visibility into what's happening.\n\nJoin the <##{channel_id}> channel to stay informed about active incidents, or explore the commands to see how FireFight can help during outages."
            }
          },
          {
            type: "actions",
            elements: [
              {
                type: "button",
                text: {
                  type: "plain_text",
                  text: "Join the channel",
                  emoji: true
                },
                url: "slack://channel?id=#{channel_id}",
                style: "primary"
              }
            ]
          }
        ]
      }
    end
  end
end
```

---

### Phase 5: Platform-Agnostic Workflow

Create a unified workflow that works for any platform using adapters.

**File:** `app/workflows/workspace_setup_workflow.rb`

```ruby
class WorkspaceSetupWorkflow < Base
  workflow_name "workspace_setup.v1"

  step :create_incidents_channel
  step :set_channel_metadata, depends_on: [:create_incidents_channel]
  step :invite_installer, depends_on: [:create_incidents_channel]
  step :post_welcome_message, depends_on: [:set_channel_metadata, :invite_installer]
  step :store_channel_id, depends_on: [:create_incidents_channel]

  # Step 1: Create incidents channel
  def create_incidents_channel(workflow:, step:, input:)
    workspace = workflow.subject
    adapter = WorkspaceAdapter.for(workspace)

    result = adapter.create_incidents_channel

    Rails.logger.info({
      event: "workspace_setup.channel_created",
      message: "Created incidents channel",
      workflow_id: workflow.id,
      workspace_id: workspace.id,
      platform: workspace.platform,
      channel_id: result[:channel_id],
      channel_name: result[:channel_name],
      already_existed: result[:already_existed]
    })

    result
  end

  # Step 2: Set channel topic and description
  def set_channel_metadata(workflow:, step:, input:)
    workspace = workflow.subject
    adapter = WorkspaceAdapter.for(workspace)
    channel_id = input[:create_incidents_channel][:channel_id]

    adapter.set_channel_metadata(channel_id: channel_id)

    Rails.logger.info({
      event: "workspace_setup.metadata_set",
      message: "Set channel topic and description",
      workflow_id: workflow.id,
      workspace_id: workspace.id,
      channel_id: channel_id
    })

    { success: true }
  end

  # Step 3: Invite installing user to channel
  def invite_installer(workflow:, step:, input:)
    workspace = workflow.subject
    adapter = WorkspaceAdapter.for(workspace)
    channel_id = input[:create_incidents_channel][:channel_id]
    installer_user_id = workflow.context[:installer_user_id]

    # Skip if channel already existed (user likely already in it)
    if input[:create_incidents_channel][:already_existed]
      Rails.logger.info({
        event: "workspace_setup.invite_skipped",
        message: "Skipping user invite, channel already existed",
        workflow_id: workflow.id,
        workspace_id: workspace.id,
        channel_id: channel_id
      })

      return { skipped: true }
    end

    adapter.invite_user(
      channel_id: channel_id,
      user_id: installer_user_id
    )

    Rails.logger.info({
      event: "workspace_setup.user_invited",
      message: "Invited installer to incidents channel",
      workflow_id: workflow.id,
      workspace_id: workspace.id,
      channel_id: channel_id,
      user_id: installer_user_id
    })

    { invited_user: installer_user_id }
  end

  # Step 4: Post welcome message with interactive buttons
  def post_welcome_message(workflow:, step:, input:)
    workspace = workflow.subject
    adapter = WorkspaceAdapter.for(workspace)
    channel_id = input[:create_incidents_channel][:channel_id]

    result = adapter.post_welcome_message(channel_id: channel_id)

    Rails.logger.info({
      event: "workspace_setup.welcome_posted",
      message: "Posted welcome message to incidents channel",
      workflow_id: workflow.id,
      workspace_id: workspace.id,
      channel_id: channel_id,
      message_ts: result[:message_ts]
    })

    result
  end

  # Step 5: Store channel ID in workspace record
  def store_channel_id(workflow:, step:, input:)
    workspace = workflow.subject
    channel_id = input[:create_incidents_channel][:channel_id]

    workspace.update!(incidents_channel_id: channel_id)

    Rails.logger.info({
      event: "workspace_setup.channel_stored",
      message: "Stored incidents channel ID in workspace",
      workflow_id: workflow.id,
      workspace_id: workspace.id,
      channel_id: channel_id
    })

    { workspace_id: workspace.id, channel_id: channel_id }
  end
end
```

---

### Phase 6: OAuth Integration

Update OAuth callback to trigger workspace setup workflow.

**File:** `app/controllers/auth/omniauth_callbacks_controller.rb`

```ruby
def slack
  auth_hash = request.env["omniauth.auth"]

  ActiveRecord::Base.transaction do
    workspace = Workspace.find_or_create_from_slack!(auth_hash)
    user = User.find_or_create_from_omniauth!(auth_hash)
    membership = WorkspaceMembership.find_or_create_from_omniauth!(
      user, workspace, auth_hash
    )

    session[:user_id] = user.id
    session[:workspace_id] = workspace.id

    # Trigger workspace setup workflow if first install
    if workspace.incidents_channel_id.blank?
      WorkspaceSetupWorkflow.start!(
        workspace,
        context: {
          installer_user_id: auth_hash.uid,
          installer_membership_id: membership.id
        }
      )

      Rails.logger.info({
        event: "auth.workspace_setup_triggered",
        message: "Started workspace setup workflow",
        workspace_id: workspace.id,
        user_id: user.id,
        installer_user_id: auth_hash.uid
      })

      flash[:notice] = "Setting up your FireFight workspace..."
    else
      flash[:notice] = "Successfully signed in with Slack!"
    end
  end

  redirect_to dashboard_path
end
```

---

### Phase 7: Interactive Components

Update interactions controller to handle button clicks and modal submissions.

**File:** `app/controllers/api/v1/interactions_controller.rb`

Add these handler methods:

```ruby
private

def handle_block_actions(payload)
  action = payload.dig(:actions, 0)
  action_id = action[:action_id]

  case action_id
  when "share_incidents_channel"
    handle_share_channel_button(payload)
  when "preview_announcement"
    handle_preview_announcement(payload)
  when "preview_homepage_disabled", "preview_subscribe_disabled"
    # These are disabled preview buttons - do nothing
    render json: { response_action: "clear" }
  when "join_incidents_channel"
    # Handled by URL, no backend action needed
    render json: { response_action: "clear" }
  else
    # Handle other actions...
    super
  end
end

def handle_view_submission(payload)
  callback_id = payload.dig(:view, :callback_id)

  case callback_id
  when "share_incidents_channel_modal"
    handle_share_modal_submission(payload)
  else
    # Handle other submissions...
    super
  end
end

def handle_share_channel_button(payload)
  workspace = find_workspace(payload)
  user_id = payload.dig(:user, :id)
  trigger_id = payload[:trigger_id]

  modal = Slack::InstallationMessageBuilder.share_channel_modal(
    user_id,
    workspace.incidents_channel_id
  )

  Slack::Client.open_modal(
    workspace: workspace,
    trigger_id: trigger_id,
    view: modal
  )

  Rails.logger.info({
    event: "interactions.share_modal_opened",
    message: "Opened share channel modal",
    workspace_id: workspace.id,
    user_id: user_id
  })

  render json: { response_action: "clear" }
rescue Slack::Client::TriggerExpiredError
  Rails.logger.warn({
    event: "interactions.trigger_expired",
    message: "Trigger ID expired when opening share modal",
    workspace_id: workspace.id,
    user_id: user_id
  })

  render json: {
    response_action: "errors",
    errors: { base: "This interaction has expired. Please try again." }
  }
end

def handle_preview_announcement(payload)
  workspace = find_workspace(payload)
  user_id = payload.dig(:user, :id)
  channel_id = payload.dig(:channel, :id)

  preview = Slack::InstallationMessageBuilder.preview_announcement_blocks(user_id)

  Slack::Client.post_ephemeral(
    workspace: workspace,
    channel: channel_id,
    user: user_id,
    text: "[PREVIEW] Website is down",
    blocks: preview[:blocks]
  )

  Rails.logger.info({
    event: "interactions.preview_posted",
    message: "Posted preview announcement",
    workspace_id: workspace.id,
    user_id: user_id,
    channel_id: channel_id
  })

  render json: { response_action: "clear" }
end

def handle_share_modal_submission(payload)
  workspace = find_workspace(payload)
  user_id = payload.dig(:user, :id)

  # Extract selected channels/users from modal
  values = payload.dig(:view, :state, :values)
  selected_conversations = values.dig(
    :share_target_block,
    :share_target_select,
    :selected_conversations
  ) || []

  if selected_conversations.empty?
    Rails.logger.warn({
      event: "interactions.share_no_targets",
      message: "User tried to share without selecting targets",
      workspace_id: workspace.id,
      user_id: user_id
    })

    return render json: {
      response_action: "errors",
      errors: { share_target_block: "Please select at least one channel or person" }
    }
  end

  # Send share message to each selected target
  share_message = Slack::InstallationMessageBuilder.share_message(
    user_id,
    workspace.incidents_channel_id
  )

  selected_conversations.each do |conversation_id|
    Slack::Client.post_message(
      workspace: workspace,
      channel: conversation_id,
      text: "FireFight is available in this workspace",
      blocks: share_message[:blocks]
    )
  end

  Rails.logger.info({
    event: "interactions.channel_shared",
    message: "Shared incidents channel",
    workspace_id: workspace.id,
    user_id: user_id,
    target_count: selected_conversations.size,
    targets: selected_conversations
  })

  render json: { response_action: "clear" }
end
```

---

### Phase 8: Additional Client Methods

Add helper method for listing channels (needed by adapter).

**File:** `app/adapters/slack/client.rb`

```ruby
# List conversations (channels)
#
# @param workspace [Workspace] The workspace to use for authentication
# @param types [String] Comma-separated list of channel types (default: "public_channel")
# @param limit [Integer] Max results per page (default: 1000)
# @return [Array<Hash>] Array of channel objects with indifferent access
def self.list_conversations(workspace:, types: "public_channel", limit: 1000)
  response = api_post(
    workspace: workspace,
    endpoint: "conversations.list",
    payload: {
      types: types,
      limit: limit
    }
  )

  response[:channels] || []
end
```

**Note:** The other methods (`create_channel`, `set_channel_topic`, `set_channel_purpose`, `invite_to_channel`) have already been added to the client in the earlier refactoring.

---

## Testing Strategy

### Console Testing

```ruby
# In Rails console
workspace = Workspace.last

# Test workflow synchronously
workflow = WorkspaceSetupWorkflow.start_inline!(
  workspace,
  context: { installer_user_id: "U12345678" }
)

# Check workflow status
workflow.state  # => "succeeded"
workflow.workflow_steps.map { |s| [s.name, s.status] }

# Check channel was created and stored
workspace.reload.incidents_channel_id  # => "C123456789"

# Check step outputs
workflow.workflow_steps.find_by(name: "create_incidents_channel").output
# => {"channel_id"=>"C123456789", "channel_name"=>"incidents", "already_existed"=>false}
```

### Integration Testing

1. **Fresh Install:**
   - Clear database: `Workspace.destroy_all`
   - Install app in test Slack workspace
   - Sign in via OAuth at `http://localhost:3000/auth/slack`
   - Verify #incidents channel created in Slack
   - Verify channel topic/description set
   - Verify welcome message posted with buttons
   - Click "Preview" button → see ephemeral preview
   - Click "Share" button → modal opens with channel selector

2. **Re-install:**
   - Keep #incidents channel in Slack
   - Clear database: `Workspace.destroy_all`
   - Re-authenticate
   - Verify workflow handles existing channel gracefully
   - Verify no duplicate messages posted

3. **Share Functionality:**
   - Click "Share this channel" button
   - Select test channel in modal
   - Submit modal
   - Verify message posted to selected channel with join button

### Error Case Testing

1. **Permissions Missing:**
   - Remove `channels:manage` scope temporarily
   - Attempt installation
   - Verify graceful error handling and logging

2. **Channel Name Conflict:**
   - Manually create #incidents channel in Slack
   - Install app
   - Verify app uses existing channel (no error)

---

## Acceptance Criteria Checklist

**Installation Flow:**
- [ ] OAuth flow completes successfully
- [ ] Workspace record created/updated in database
- [ ] #incidents channel created (or existing one used)
- [ ] Channel topic set correctly
- [ ] Channel description set correctly
- [ ] Installing user added to channel
- [ ] Welcome message posted to channel with correct text
- [ ] Both action buttons present and visible
- [ ] User redirected to dashboard
- [ ] All events logged with structured JSON

**Share Channel Button:**
- [ ] Opens modal when clicked
- [ ] Modal shows correct title: "Share this channel"
- [ ] Modal description mentions clicking user by name
- [ ] Body text correct
- [ ] Channel selector works (multi-select)
- [ ] Share button sends message to selected recipients
- [ ] "Join the channel" button works

**Preview Announcement Button:**
- [ ] Shows ephemeral message only to clicking user
- [ ] Preview displays with correct formatting
- [ ] Shows "Only visible to you" at top
- [ ] Shows "[PREVIEW] Website is down" as title
- [ ] Shows all metadata fields with correct emojis
- [ ] Buttons visible but non-functional

**Error Cases:**
- [ ] Handles channel already exists gracefully
- [ ] Handles missing permissions with clear error
- [ ] Installation continues even if channel creation fails
- [ ] All errors logged with structured JSON

---

## Architecture Notes

### Adapter Pattern

The implementation follows the existing adapter pattern in the codebase:

```
Workflow (platform-agnostic)
    ↓
Adapter (platform-specific logic)
    ↓
Client (low-level API calls)
```

**Benefits:**
- Single workflow works for Slack and Teams (future)
- Platform differences isolated in adapters
- Easy to test (mock adapter, not HTTP)
- Follows existing codebase patterns

**Factory Pattern:**

The `WorkspaceAdapter.for(workspace)` factory method automatically instantiates the correct adapter:

```ruby
# In workflow - no platform conditionals needed!
adapter = WorkspaceAdapter.for(workspace)
result = adapter.create_incidents_channel
```

This eliminates platform-switching logic from workflows and centralizes it in one place. Benefits:
- **DRY**: Platform detection logic in one place
- **Clean workflows**: No case statements in business logic
- **Easy to extend**: Add new platform by creating adapter class
- **Type safety**: Returns typed adapter instances

### Structured Logging

All logs follow the structured JSON pattern used throughout the codebase:

```ruby
Rails.logger.info({
  event: "namespace.action",           # Dot-separated event name
  message: "Human-readable message",   # What happened
  workflow_id: workflow.id,            # Context
  workspace_id: workspace.id,
  # ... other relevant data
})
```

This enables:
- Easy filtering: `event:"workspace_setup.*"`
- Structured queries in log aggregators
- Consistent logging across the application

### Symbol vs String Keys

Following Rails conventions:
- Use **symbols** for hash keys in Ruby code
- API responses use `with_indifferent_access` (supports both)
- Access using symbols: `result[:channel_id]`

---

## Copy Specifications

**Channel Topic/Description:**
```
FireFight announcements channel. Every time someone declares an incident, we'll announce it here, and make sure the post is always up to date.
```

**Welcome Message:**
```
Welcome to FireFight!

This is your central incident hub.

When an incident is declared, we'll spin up a dedicated response channel
and post an announcement here. Each announcement stays current as the
incident evolves, giving you real-time visibility across all ongoing
incidents in your organization.
```

**Share Modal Message:**
```
👋 @[Username] is using FireFight in your Slack workspace

FireFight helps your team manage incidents with better coordination and
full visibility into what's happening.

Join the #incidents channel to stay informed about active incidents,
or explore the commands to see how FireFight can help during outages.
```

---

## Dependencies

- Slack API permissions: `channels:manage`, `channels:join`, `channels:read`, `users:read` ✅ Already added
- SOLID workflow engine ✅ Already implemented
- HTTParty for HTTP requests ✅ Already in use
- Rails 8.1 encrypted attributes ✅ Already configured
- Existing adapter pattern ✅ Already established

---

## Future Enhancements (Out of Scope for FIR-10)

- Interactive tutorial in #incidents channel
- Customizable welcome message
- Multiple announcement channels per workspace
- Custom channel naming (e.g., #firefight-incidents)
- Channel configuration UI in dashboard
- Functional "Incident homepage" and "Subscribe" buttons in preview
- Pin welcome message to channel

---

## References

- Linear Issue: FIR-10
- Slack API: https://api.slack.com/methods
- Block Kit Builder: https://app.slack.com/block-kit-builder
- Competitor Analysis: Screenshot showing incident.io share modal implementation
- Existing Patterns: `app/adapters/slack/`, `app/workflows/example_calculation_workflow.rb`
