# Authentication System Documentation

## Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Database Schema](#database-schema)
- [OAuth Flow](#oauth-flow)
- [Required Credentials](#required-credentials)
- [Token Management](#token-management)
- [Usage Guide](#usage-guide)
- [Troubleshooting](#troubleshooting)
- [Future Extensibility](#future-extensibility)

---

## Overview

Firefight uses a **multi-provider OAuth 2.0 authentication system** designed to support multiple workspace platforms (currently Slack, with Microsoft Teams support planned).

### Key Features
- ✅ Platform-agnostic architecture (Slack today, Teams tomorrow)
- ✅ Multi-workspace support (users can belong to multiple workspaces)
- ✅ Role-based access control (owner, admin, member)
- ✅ Automatic token refresh (tokens expire after 12 hours)
- ✅ String-based enums for better readability
- ✅ UUID primary keys
- ✅ Encrypted token storage

### Technology Stack
- **Backend**: Ruby on Rails 8.1
- **Frontend**: React 19 + Inertia.js + TypeScript
- **OAuth**: Custom OmniAuth strategy for Slack OAuth v2
- **Token Refresh**: Background job via Solid Queue
- **UI**: shadcn/ui + Tailwind CSS

---

## Architecture

### Authentication Flow
```
User clicks "Sign in with Slack"
    ↓
Redirects to /auth/slack (OmniAuth)
    ↓
Slack OAuth authorization page
    ↓
User authorizes in Slack
    ↓
Slack redirects to /auth/slack/callback
    ↓
Backend processes OAuth response:
  - Find or create Workspace
  - Find or create User
  - Create WorkspaceMembership (first user = owner)
  - Set session (user_id, workspace_id)
    ↓
Redirect to /dashboard
    ↓
User is authenticated!
```

### Directory Structure
```
app/
├── controllers/
│   ├── application_controller.rb      # Auth helpers
│   ├── inertia_controller.rb          # Shares user/workspace data
│   ├── sessions_controller.rb         # Login/logout
│   ├── dashboard_controller.rb        # Authenticated pages
│   └── auth/
│       └── omniauth_callbacks_controller.rb  # OAuth callback handler
├── models/
│   ├── user.rb                        # Application users
│   ├── workspace.rb                   # Slack workspaces
│   └── workspace_membership.rb        # User-workspace relationships
├── jobs/
│   └── refresh_slack_tokens_job.rb    # Hourly token refresh
└── services/
    └── slack/
        └── token_refresh_service.rb   # Token refresh logic

config/
├── initializers/
│   └── omniauth.rb                    # OmniAuth configuration
├── slack_manifests/
│   ├── development.yml                # Slack app config (dev)
│   └── production.yml                 # Slack app config (prod)
└── recurring.yml                      # Scheduled jobs

lib/
├── omniauth/
│   └── strategies/
│       └── slack.rb                   # Custom Slack OAuth strategy
├── slack/
│   └── manifest_reader.rb             # Reads scopes from manifest
└── tasks/
    └── slack.rake                     # Manual token refresh tasks
```

---

## Database Schema

### Tables Overview

We use **3 main tables** for authentication:

1. **`workspaces`** - Slack workspaces/teams
2. **`users`** - Application users (identified by email)
3. **`workspace_memberships`** - Join table linking users to workspaces with roles

### Detailed Schema

#### `workspaces` Table
Stores information about connected Slack workspaces.

```ruby
create_table :workspaces, id: :uuid do |t|
  t.string   :platform              # 'slack' or 'teams'
  t.string   :platform_id           # Slack team ID (e.g., T01234567)
  t.string   :name                  # Workspace name
  t.string   :avatar_url            # Workspace icon
  t.jsonb    :platform_data         # Additional Slack metadata
  t.text     :access_token          # Encrypted bot token
  t.text     :refresh_token         # Encrypted refresh token
  t.datetime :token_expires_at      # When token expires
  t.datetime :installed_at          # When workspace was connected
  t.timestamps
end

# Indexes
add_index :workspaces, [:platform, :platform_id], unique: true
add_index :workspaces, :platform
```

**Key Points:**
- `platform`: String enum ('slack', 'teams') - not an integer!
- `access_token`: Encrypted using Rails 7+ native encryption
- `platform_id`: Unique identifier from Slack (team ID)
- `platform_data`: JSONB for storing Slack-specific data

#### `users` Table
Stores application users, identified by email.

```ruby
create_table :users, id: :uuid do |t|
  t.string :email                   # Unique user email
  t.string :name                    # User's display name
  t.string :avatar_url              # Profile picture
  t.timestamps
end

# Indexes
add_index :users, :email, unique: true
```

**Key Points:**
- Users are identified by **email** across all platforms
- Same user can belong to multiple workspaces
- Email is unique constraint

#### `workspace_memberships` Table
Join table linking users to workspaces with roles.

```ruby
create_table :workspace_memberships, id: :uuid do |t|
  t.uuid     :user_id               # FK to users
  t.uuid     :workspace_id          # FK to workspaces
  t.string   :platform_user_id      # Slack user ID (U1234567)
  t.string   :role                  # 'member', 'admin', or 'owner'
  t.jsonb    :platform_data         # Slack user metadata
  t.text     :access_token          # Encrypted user token
  t.text     :refresh_token         # Encrypted refresh token
  t.datetime :token_expires_at      # When user token expires
  t.datetime :joined_at             # When user joined workspace
  t.timestamps
end

# Indexes
add_index :workspace_memberships, [:workspace_id, :platform_user_id], unique: true
add_index :workspace_memberships, :role
```

**Key Points:**
- `role`: String enum ('member', 'admin', 'owner') - not an integer!
- First user to connect workspace gets `role: 'owner'`
- Subsequent users get `role: 'member'`
- `platform_user_id`: Slack's internal user ID (different from email)

### Migration File
All tables are created in a single migration for clarity:
```
db/migrate/20251127104549_create_authentication_tables.rb
```

---

## OAuth Flow

### Step-by-Step Process

#### 1. User Initiates Sign-In
**Frontend:** User clicks "Sign in with Slack" button
```tsx
// app/frontend/components/auth/slack-auth-button.tsx
<Button onClick={() => window.location.href = Routes.authProviderCallbackPath({ provider: 'slack' })}>
  Sign in with Slack
</Button>
```

**Route:** `GET /auth/slack` (handled by OmniAuth)

#### 2. OmniAuth Redirects to Slack
OmniAuth constructs Slack OAuth URL:
```
https://slack.com/oauth/v2/authorize?
  client_id=YOUR_CLIENT_ID&
  scope=users:read,users:read.email,team:read&
  redirect_uri=http://localhost:3000/auth/slack/callback
```

#### 3. User Authorizes in Slack
- Slack shows permission screen
- User authorizes the app
- Slack redirects back to callback URL with authorization code

#### 4. OmniAuth Exchanges Code for Token
OmniAuth automatically:
- Receives authorization code
- Calls `https://slack.com/api/oauth.v2.access`
- Exchanges code for access tokens
- Creates auth hash with user/team data

#### 5. Callback Handler Processes Response
**Controller:** `Auth::OmniauthCallbacksController#slack`

```ruby
def slack
  auth_hash = request.env['omniauth.auth']

  ActiveRecord::Base.transaction do
    # Find or create workspace from Slack team
    workspace = Workspace.find_or_create_from_slack!(auth_hash)

    # Find or create user from email
    user = User.find_or_create_from_omniauth!(auth_hash)

    # Create membership (first user = owner, rest = member)
    membership = WorkspaceMembership.find_or_create_from_omniauth!(
      user, workspace, auth_hash
    )

    # Set session
    session[:user_id] = user.id
    session[:workspace_id] = workspace.id
  end

  redirect_to dashboard_path
end
```

#### 6. User is Authenticated
- Session contains `user_id` and `workspace_id`
- `current_user` and `current_workspace` helpers work
- Inertia shares user/workspace data with frontend

### Auth Hash Structure
The auth hash from OmniAuth contains:

```ruby
{
  provider: 'slack',
  uid: 'U01234567',  # Slack user ID
  info: {
    name: 'John Doe',
    email: 'john@example.com',
    image: 'https://avatars.slack-edge.com/...',
    team_id: 'T01234567',
    team_name: 'Acme Corp'
  },
  credentials: {
    token: 'xoxb-1234567890-...',  # Access token
    refresh_token: 'xoxe-1-...',   # Refresh token (for rotation)
    expires_at: 1234567890          # Unix timestamp
  },
  extra: {
    team_info: { ... },  # Full team data from Slack
    user_info: { ... }   # Full user data from Slack
  }
}
```

---

## Required Credentials

### Where to Get Credentials

1. **Go to Slack App Dashboard:**
   https://api.slack.com/apps

2. **Create New App:**
   - Click "Create New App"
   - Select "From an app manifest"
   - Choose your workspace
   - Copy contents of `config/slack_manifests/development.yml`
   - Paste and create

3. **Get Credentials:**
   Navigate to **Basic Information** → **App Credentials**

   You'll see:
   - **Client ID**: `1234567890.1234567890` (public)
   - **Client Secret**: `abc123...` (secret, never commit!)
   - **Signing Secret**: `xyz789...` (for webhook verification)

### Required Variables

| Variable | Description | Example | Where Used |
|----------|-------------|---------|------------|
| `SLACK_CLIENT_ID` | OAuth client ID | `1234567890.1234567890` | OAuth flow, token refresh |
| `SLACK_CLIENT_SECRET` | OAuth client secret | `abc123def456...` | OAuth flow, token refresh |
| `SLACK_SIGNING_SECRET` | Webhook verification | `xyz789abc...` | Future: webhook events |

### How to Store Credentials

#### Option 1: Rails Credentials (Production)
```bash
bin/rails credentials:edit
```

Add:
```yaml
slack:
  development:
    client_id: "your-dev-client-id"
    client_secret: "your-dev-client-secret"
    signing_secret: "your-dev-signing-secret"
  production:
    client_id: "your-prod-client-id"
    client_secret: "your-prod-client-secret"
    signing_secret: "your-prod-signing-secret"
```

#### Option 2: Environment Variables (Alternative)
Create `.env` (don't commit):
```bash
SLACK_CLIENT_ID=1234567890.1234567890
SLACK_CLIENT_SECRET=abc123def456...
SLACK_SIGNING_SECRET=xyz789abc...
```

**Note:** Our code currently reads from Rails credentials. To support ENV vars, update `lib/slack/token_refresh_service.rb` to check ENV first.

### OAuth Scopes

Scopes are **automatically read from manifest files** based on environment:
- Development: `config/slack_manifests/development.yml`
- Production: `config/slack_manifests/production.yml`

Current scopes:
```yaml
oauth_config:
  scopes:
    user:
      - users:read          # Read user profile
      - users:read.email    # Read user email
    bot:
      - team:read           # Read workspace info
```

**To add more scopes:**
1. Edit manifest file
2. Re-upload to Slack app dashboard
3. Existing users must re-authorize

---

## Token Management

### Token Lifecycle

#### 1. Initial Token Receipt
When user authenticates:
- Slack provides `access_token` and `refresh_token`
- Tokens expire in **12 hours** (with rotation enabled)
- Stored encrypted in database

#### 2. Token Expiration
- `token_expires_at` is set to 12 hours from issuance
- System checks expiration every hour

#### 3. Automatic Refresh
**Job:** `RefreshSlackTokensJob` runs every hour

**Process:**
1. Find tokens expiring in next 3 hours
2. Call Slack API to refresh
3. Update database with new tokens
4. Log success/failure

**Why 3 hours buffer?**
- Gives you time to fix issues if refresh fails
- Token valid for 9 more hours after refresh
- Prevents last-minute failures

### Token Refresh Service

All refresh logic is in: `app/services/slack/token_refresh_service.rb`

**Methods:**
```ruby
service = Slack::TokenRefreshService.new

# Refresh specific workspace
service.refresh_workspace(workspace)  # => true/false

# Refresh specific membership
service.refresh_membership(membership)  # => true/false

# Refresh all expiring tokens
service.refresh_all_expiring(buffer: 3.hours)  # => results hash

# Check if refresh needed
service.refresh_needed?(workspace, buffer: 3.hours)  # => true/false
```

### Manual Token Refresh

#### Via Rails Console
```ruby
# Find workspace
workspace = Workspace.find_by(name: "Acme Corp")

# Refresh token
service = Slack::TokenRefreshService.new
result = service.refresh_workspace(workspace)

puts "Success!" if result
workspace.reload.token_expires_at  # Check new expiration
```

#### Via Rake Tasks
```bash
# Refresh specific workspace
bin/rails slack:refresh_workspace[workspace-uuid]

# Refresh specific membership
bin/rails slack:refresh_membership[membership-uuid]

# Refresh all expiring tokens
bin/rails slack:refresh_all_expiring

# Force refresh all workspaces (ignore expiration)
bin/rails slack:force_refresh_all_workspaces

# List all workspaces with token status
bin/rails slack:list_workspaces
```

### Token Refresh API Call

**Endpoint:** `POST https://slack.com/api/oauth.v2.access`

**Request Body:**
```json
{
  "client_id": "your-client-id",
  "client_secret": "your-client-secret",
  "grant_type": "refresh_token",
  "refresh_token": "xoxe-1-..."
}
```

**Response:**
```json
{
  "ok": true,
  "access_token": "xoxb-new-token...",
  "refresh_token": "xoxe-new-refresh...",
  "expires_in": 43200  // 12 hours in seconds
}
```

### Scheduled Refresh Job

**Configuration:** `config/recurring.yml`

```yaml
development:
  refresh_slack_tokens:
    class: RefreshSlackTokensJob
    schedule: every hour

production:
  refresh_slack_tokens:
    class: RefreshSlackTokensJob
    schedule: every hour
```

**Monitoring:**
```bash
# Check logs for refresh activity
tail -f log/production.log | grep "Slack Token Refresh"

# Sample log output:
# [Slack Token Refresh] Successfully refreshed workspace token for Acme Corp (uuid)
# [Slack Token Refresh] Summary: Workspaces (5 succeeded, 0 failed), Memberships (12 succeeded, 0 failed)
```

---

## Usage Guide

### For Developers

#### Setting Up Locally

1. **Create Slack App:**
   - Go to https://api.slack.com/apps
   - Create from manifest: `config/slack_manifests/development.yml`
   - Copy Client ID, Client Secret, Signing Secret

2. **Add Credentials:**
   ```bash
   bin/rails credentials:edit
   ```
   Add Slack credentials (see [Required Credentials](#required-credentials))

3. **Start Server:**
   ```bash
   bin/dev
   ```

4. **Test OAuth Flow:**
   - Visit http://localhost:3000
   - Click "Sign in with Slack"
   - Authorize in Slack
   - Should redirect to dashboard

#### Authentication Helpers

**In Controllers:**
```ruby
class DashboardController < InertiaController
  before_action :require_authentication

  def index
    # current_user and current_workspace are available
    render inertia: 'dashboard/index'
  end
end
```

**Helper Methods:**
```ruby
current_user          # => User instance or nil
current_workspace     # => Workspace instance or nil
user_signed_in?       # => true/false
require_authentication # Redirect to login if not signed in
```

**In Views/Inertia:**
```tsx
import { usePage } from '@inertiajs/react'
import { SharedProps } from '@/types'

function MyComponent() {
  const { currentUser, currentWorkspace } = usePage<SharedProps>().props

  return (
    <div>
      Welcome, {currentUser?.name}!
      Workspace: {currentWorkspace?.name}
    </div>
  )
}
```

### For Operations

#### Production Deployment

1. **Set Up Slack App:**
   - Create production Slack app from `config/slack_manifests/production.yml`
   - Update redirect URL to production domain

2. **Add Production Credentials:**
   ```bash
   bin/rails credentials:edit --environment production
   ```

3. **Deploy:**
   - Ensure `RAILS_MASTER_KEY` is set in production environment
   - Deploy code
   - Run migrations: `bin/rails db:migrate`

4. **Verify Token Refresh:**
   - Check Solid Queue is running
   - Monitor logs for refresh activity

#### Monitoring

**Check Token Status:**
```bash
bin/rails slack:list_workspaces
```

**Manual Refresh if Needed:**
```bash
bin/rails slack:refresh_workspace[workspace-id]
```

**Console Debugging:**
```ruby
# Find problematic workspace
workspace = Workspace.find('uuid')

# Check token status
workspace.token_expires_at
workspace.refresh_token.present?

# Try manual refresh
service = Slack::TokenRefreshService.new
service.refresh_workspace(workspace)
```

---

## Troubleshooting

### Common Issues

#### 1. OAuth Callback Error: "invalid_client_id"

**Cause:** Client ID/Secret mismatch or not set

**Fix:**
```bash
bin/rails credentials:edit
# Verify slack.development.client_id matches Slack app
```

#### 2. Token Refresh Fails

**Symptoms:** Logs show "Failed to refresh token"

**Debug:**
```ruby
workspace = Workspace.find('uuid')
workspace.refresh_token.present?  # Should be true
workspace.token_expires_at        # Should be a future time

# Try manual refresh with verbose output
service = Slack::TokenRefreshService.new
result = service.refresh_workspace(workspace)
# Check logs for detailed error
```

**Common Causes:**
- Slack app was uninstalled from workspace
- Client secret changed in Slack app dashboard
- Token rotation not enabled in Slack app

#### 3. User Can't Access Workspace

**Symptoms:** User authenticated but sees error

**Debug:**
```ruby
user = User.find_by(email: 'user@example.com')
user.workspaces  # Should show at least one workspace

# Check membership
membership = WorkspaceMembership.find_by(user: user)
membership.role  # Check role
```

#### 4. Multiple Users, Only One is Owner

**Expected Behavior:** First user to connect workspace = owner

**Verify:**
```ruby
workspace = Workspace.find_by(name: "Workspace Name")
workspace.workspace_memberships.owners
# Should return the first user who connected
```

**To Promote Another User:**
```ruby
membership = WorkspaceMembership.find_by(user: user, workspace: workspace)
membership.update!(role: 'owner')
```

### Logging

**Enable Detailed Logging:**
```ruby
# config/environments/development.rb
config.log_level = :debug
```

**Key Log Messages:**
```
[Slack Token Refresh] Successfully refreshed workspace token for...
[Slack Token Refresh] Failed to refresh token for...: error_message
[Slack OAuth] Processing callback for user@example.com
```

---

## Future Extensibility

### Adding Microsoft Teams

Our architecture is designed for easy multi-provider support:

#### 1. Add Teams OAuth Strategy
```ruby
# lib/omniauth/strategies/teams.rb
class Teams < OmniAuth::Strategies::OAuth2
  # Microsoft Teams OAuth implementation
end
```

#### 2. Create Teams Manifest
```yaml
# config/teams_manifests/development.yml
# Microsoft Teams app configuration
```

#### 3. Update Models
Already support `platform: 'teams'` enum - no changes needed!

#### 4. Add Teams-Specific Logic
```ruby
# app/models/workspace.rb
def self.find_or_create_from_teams!(auth_hash)
  # Similar to find_or_create_from_slack!
end
```

### Expanding RBAC

Current roles are a foundation for richer permissions:

**Current:**
```ruby
enum :role, { member: 'member', admin: 'admin', owner: 'owner' }
```

**Future Options:**

**Option A: More Roles**
```ruby
enum :role, {
  viewer: 'viewer',
  member: 'member',
  manager: 'manager',
  admin: 'admin',
  owner: 'owner'
}
```

**Option B: Permission System**
```ruby
# New table: permissions
# Columns: workspace_membership_id, permission_name
# Examples: 'manage_billing', 'view_analytics', 'manage_members'

membership.permissions.include?('manage_billing')
```

**Option C: Role-Permission Matrix**
```ruby
# New tables: roles, permissions, role_permissions
# Fully customizable roles with any permission combination
```

### Multi-Workspace Support

Already built in! Users can belong to multiple workspaces:

```ruby
user.workspaces  # All workspaces user belongs to
user.workspace_memberships  # All memberships with roles

# Switch workspace in session
session[:workspace_id] = another_workspace.id
```

**Frontend Enhancement:**
Add workspace switcher dropdown in nav bar to let users switch between workspaces.

---

## API Reference

### Models

#### User
```ruby
# Associations
has_many :workspace_memberships
has_many :workspaces, through: :workspace_memberships

# Class Methods
User.find_or_create_from_omniauth!(auth_hash)

# Instance Methods
user.member_of?(workspace)
user.membership_in(workspace)
user.owner_of?(workspace)
user.admin_of?(workspace)
```

#### Workspace
```ruby
# Enums
enum :platform, { slack: 'slack', teams: 'teams' }

# Associations
has_many :workspace_memberships
has_many :users, through: :workspace_memberships

# Scopes
Workspace.by_platform('slack')
Workspace.slack_platform
Workspace.recent

# Class Methods
Workspace.find_or_create_from_slack!(auth_hash)

# Instance Methods
workspace.token_expired?
workspace.slack_platform?  # from enum suffix
workspace.teams_platform?  # from enum suffix
```

#### WorkspaceMembership
```ruby
# Enums
enum :role, { member: 'member', admin: 'admin', owner: 'owner' }

# Associations
belongs_to :user
belongs_to :workspace

# Scopes
WorkspaceMembership.by_role('owner')
WorkspaceMembership.owners
WorkspaceMembership.admins
WorkspaceMembership.members

# Class Methods
WorkspaceMembership.find_or_create_from_omniauth!(user, workspace, auth_hash)

# Instance Methods
membership.member_role?  # from enum suffix
membership.admin_role?   # from enum suffix
membership.owner_role?   # from enum suffix
```

### Services

#### Slack::TokenRefreshService
```ruby
service = Slack::TokenRefreshService.new

# Refresh specific records
service.refresh_workspace(workspace)  # => Boolean
service.refresh_membership(membership)  # => Boolean

# Refresh all expiring
service.refresh_all_expiring(buffer: 3.hours)  # => Hash with results

# Check status
service.refresh_needed?(record, buffer: 3.hours)  # => Boolean
```

### Rake Tasks

```bash
# Workspace operations
bin/rails slack:refresh_workspace[uuid]
bin/rails slack:force_refresh_all_workspaces
bin/rails slack:list_workspaces

# Membership operations
bin/rails slack:refresh_membership[uuid]

# Bulk operations
bin/rails slack:refresh_all_expiring
```

---

## Security Considerations

### Token Storage
- ✅ All tokens encrypted at rest using Rails `encrypts`
- ✅ Encryption keys derived from `RAILS_MASTER_KEY`
- ✅ Never log tokens or credentials

### CSRF Protection
- ✅ OmniAuth CSRF protection enabled
- ✅ Rails CSRF tokens on all forms
- ✅ Inertia automatically includes CSRF token

### Session Security
- ✅ Encrypted cookies for sessions
- ✅ HTTP-only cookies (no JavaScript access)
- ✅ Secure flag in production (HTTPS only)

### Token Rotation
- ✅ Tokens expire after 12 hours
- ✅ Automatic refresh before expiration
- ✅ Old tokens invalidated after refresh

### Access Control
- ✅ `require_authentication` filter on protected routes
- ✅ Current workspace checked on each request
- ✅ Role-based access ready for expansion

---

## Resources

### Documentation
- [Slack OAuth Documentation](https://api.slack.com/authentication/oauth-v2)
- [Slack Token Rotation](https://api.slack.com/authentication/rotation)
- [OmniAuth](https://github.com/omniauth/omniauth)
- [Rails Encrypted Credentials](https://guides.rubyonrails.org/security.html#custom-credentials)

### Internal Files
- Slack OAuth Strategy: `lib/omniauth/strategies/slack.rb`
- Token Refresh Service: `app/services/slack/token_refresh_service.rb`
- Rake Tasks: `lib/tasks/slack.rake`
- Manifests: `config/slack_manifests/`

### Support
For questions or issues, check:
1. Application logs: `log/development.log` or `log/production.log`
2. Rails console for debugging
3. Slack API documentation for OAuth errors

---

**Last Updated:** November 27, 2025
**Version:** 1.0
**Maintainer:** Firefight Team
