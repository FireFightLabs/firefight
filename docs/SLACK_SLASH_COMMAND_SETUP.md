# Slack Slash Command Setup Guide

This guide will help you set up and test the `/firefight` and `/ff` slash commands.

## Architecture Overview

The implementation follows a clean, platform-agnostic architecture:

```
Slack → API Controller → Background Job → Adapter → Dispatcher → Handler → Slack API
```

### Key Components

- **API Controllers** (`app/controllers/api/v1/`)
  - `commands_controller.rb` - Receives slash commands
  - `interactions_controller.rb` - Handles modal submissions
  - `base_controller.rb` - Shared JSON API functionality

- **Slack Adapters** (`app/adapters/slack/`)
  - `command_adapter.rb` - Converts Slack payloads to platform-agnostic Commands
  - `modal_builder.rb` - Builds Block Kit modal JSON
  - `client.rb` - Wrapper for Slack Web API
  - `signature_verifier.rb` - Verifies Slack request signatures

- **Platform-Agnostic Core** (`app/services/`, `app/models/`)
  - `command.rb` - Generic command object (works with any platform)
  - `command_dispatcher.rb` - Routes commands to handlers
  - `commands/modal_handler.rb` - Opens incident creation modal

- **Background Processing** (`app/jobs/`)
  - `process_command_job.rb` - Async command processing

## Setup Steps

### 1. Add Slack Signing Secret to Credentials

The signing secret is required to verify requests from Slack.

```bash
# For development
EDITOR="code --wait" bin/rails credentials:edit --environment development
```

Add the signing secret:

```yaml
slack:
  client_id: "existing..."
  client_secret: "existing..."
  signing_secret: "YOUR_SIGNING_SECRET_HERE"  # Add this line
```

**Where to find the signing secret:**
1. Go to https://api.slack.com/apps
2. Select your Firefight app
3. Go to "Basic Information"
4. Scroll to "App Credentials"
5. Copy the "Signing Secret"

Repeat for staging and production environments.

### 2. Add Slack App ID to Credentials

Each environment needs its Slack App ID configured:

```bash
# For development
EDITOR="code --wait" bin/rails credentials:edit --environment development
```

Add the app ID:

```yaml
slack:
  client_id: "existing..."
  client_secret: "existing..."
  signing_secret: "existing..."
  app_id: "YOUR_APP_ID_HERE"  # Add this line
```

**Where to find the App ID:**
1. Go to https://api.slack.com/apps
2. Select your Firefight app
3. The App ID is at the top of "Basic Information" (starts with `A`)

Repeat for staging and production environments.

### 3. Update Slack App Manifest

The manifest files are version controlled in:

- `config/slack_manifests/development.yml`
- `config/slack_manifests/staging.yml`
- `config/slack_manifests/production.yml`

#### Option A: Push via CLI (Recommended)

Install the Slack CLI and push manifests programmatically:

```bash
# Install Slack CLI
brew install slack-cli

# Login to Slack (one-time setup)
slack login

# Push manifest to development
bin/rails slack:manifest:push[development]

# Or for production
bin/rails slack:manifest:push[production]
```

**Available rake tasks:**
- `slack:manifest:push[env]` - Push manifest to Slack
- `slack:manifest:validate[env]` - Validate manifest syntax
- `slack:manifest:info[env]` - Show current configuration

#### Option B: Manual Update (Fallback)

If you prefer to update manually or don't have the Slack CLI installed:

1. Go to https://api.slack.com/apps
2. Select your Firefight app
3. Go to "App Manifest"
4. Copy the contents of the appropriate manifest file
5. Paste and save

**Important:** For local development, you'll need to use ngrok or a similar tool to expose your local server to Slack.

### 4. Set Up ngrok for Local Development

Slack needs to reach your local server. Use ngrok:

```bash
# Install ngrok (if not already installed)
brew install ngrok

# Start ngrok
ngrok http 3000
```

Copy the ngrok URL (e.g., `https://abc123.ngrok.io`) and update your development manifest:

```yaml
features:
  slash_commands:
    - command: /firefight
      url: https://YOUR-NGROK-URL.ngrok.io/api/v1/commands
    - command: /ff
      url: https://YOUR-NGROK-URL.ngrok.io/api/v1/commands
  interactivity:
    request_url: https://YOUR-NGROK-URL.ngrok.io/api/v1/interactions
```

### 5. Reinstall Slack App

After updating the manifest, you need to reinstall the app to your workspace:

1. Go to "Install App" in the Slack app settings
2. Click "Reinstall to Workspace"
3. Approve the new permissions (`commands` and `chat:write`)

### 6. Start Your Rails Server

```bash
bin/dev
```

Or if using foreman:

```bash
foreman start
```

## Testing the Slash Commands

### Test 1: Basic Command

In any Slack channel where the Firefight app is installed:

```
/firefight
```

**Expected behavior:**
1. You should see a modal appear immediately (<3 seconds)
2. The modal should have three fields:
   - Incident Title (text input)
   - Description (textarea, optional)
   - Severity (dropdown with Critical/High/Medium/Low)

### Test 2: Short Alias

```
/ff
```

**Expected behavior:**
- Same as `/firefight` - modal should appear

### Test 3: Modal Submission

1. Type `/firefight`
2. Fill in the modal:
   - Title: "Test incident"
   - Description: "Testing the modal"
   - Severity: High
3. Click "Create"

**Expected behavior:**
- Modal closes
- Check your Rails logs - you should see the submission logged
- Currently, the modal submission doesn't create anything (stub implementation)

## Debugging

### Check Rails Logs

In your terminal where `bin/dev` is running, you should see:

```
Slack interaction received: view_submission
Payload: {...}
Modal submitted
Callback ID: incident_creation_modal
Values: {...}
```

### Verify Signature Verification

If you get "Unauthorized" errors, check:

1. Signing secret is correctly added to credentials
2. ngrok URL is correct in Slack manifest
3. Request is coming from Slack (not a browser/Postman)

### Common Issues

**"Workspace not found" error:**
- Make sure you've authenticated via OAuth first
- The Slack workspace must be in your database
- Check `Workspace.where(platform: "slack")`

**Modal doesn't appear:**
- Check Rails logs for errors
- Verify background job is running (Solid Queue)
- Check that trigger_id hasn't expired (must open modal within 3s)

**"command not found" in Slack:**
- Slash commands not added to manifest
- App not reinstalled after manifest update
- Check app is installed to the workspace

## Architecture Benefits

### Platform Agnostic

The core logic knows nothing about Slack:

```ruby
# Platform-agnostic command object
command = Command.new(
  platform: "slack",
  workspace_id: "...",
  user_id: "...",
  text: "..."
)

# Platform-agnostic dispatcher
CommandDispatcher.dispatch(command)
```

### Easy to Extend

**Add a new command:**

```ruby
# app/services/commands/status_handler.rb
module Commands
  class StatusHandler
    def self.execute(command)
      # Implementation
    end
  end
end

# Update dispatcher
case command.subcommand
when "status"
  Commands::StatusHandler
end
```

**Add Teams support:**

```ruby
# app/adapters/teams/command_adapter.rb
module Teams
  class CommandAdapter < ::CommandAdapter
    def self.parse(payload)
      Command.new(
        platform: "teams",
        # ...
      )
    end
  end
end
```

## Next Steps

### Immediate

1. Add signing secret and app ID to credentials
2. Install Slack CLI (`brew install slack-cli`)
3. Login to Slack CLI (`slack login`)
4. Set up ngrok
5. Push Slack manifest (`bin/rails slack:manifest:push[development]`)
6. Test slash commands

### Future Implementation

- [ ] Implement actual incident creation in `InteractionsController#handle_view_submission`
- [ ] Add `Incident` model and database table
- [ ] Create workflow for incident creation (channel, notifications, etc.)
- [ ] Add more slash command handlers (status, list, help)
- [ ] Add rate limiting
- [ ] Add usage analytics
- [ ] Add Teams support using the same adapter pattern

## API Endpoints

### POST /api/v1/commands

Receives Slack slash commands.

**Request:** (from Slack)
```
team_id=T123
user_id=U456
command=/firefight
text=
trigger_id=123.456.abc
channel_id=C789
...
```

**Response:**
```json
{"ok": true}
```

### POST /api/v1/interactions

Receives Slack interactive component submissions.

**Request:** (from Slack)
```
payload={"type":"view_submission", ...}
```

**Response:**
```json
{"ok": true}
```

## File Structure

```
app/
├── controllers/api/v1/
│   ├── base_controller.rb           # JSON API base
│   ├── commands_controller.rb       # Slash commands
│   └── interactions_controller.rb   # Modal submissions
├── adapters/
│   ├── command_adapter.rb           # Interface for all platforms
│   └── slack/
│       ├── command_adapter.rb       # Slack → Command
│       ├── modal_builder.rb         # Block Kit modals
│       └── client.rb                # Slack Web API wrapper
├── models/
│   └── command.rb                   # Platform-agnostic PORO
├── services/
│   ├── command_dispatcher.rb        # Routes commands
│   ├── commands/
│   │   └── modal_handler.rb         # Opens modal
│   └── slack/
│       └── signature_verifier.rb    # Security
└── jobs/
    └── process_command_job.rb       # Background processing
```

## Questions?

Check the inline comments in the code for detailed explanations of each component.
