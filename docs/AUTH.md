# Authentication

## Table of Contents
- [Overview](#overview)
- [Sign-in & Membership Decision Tree](#sign-in--membership-decision-tree)
- [Two-Step Slack Auth Flow](#two-step-slack-auth-flow)
- [Membership Provisioning](#membership-provisioning)
- [Architecture](#architecture)
- [Database Schema](#database-schema)
- [Configuration](#configuration)
- [Token Management](#token-management)
- [Local Development](#local-development)
- [Deployment](#deployment)
- [Troubleshooting](#troubleshooting)
- [Future Work](#future-work)

---

## Overview

Firefight uses a **two-step Slack auth flow** that separates user identity (OpenID Connect) from bot installation (OAuth v2). This is the same pattern used by incident.io and Linear and solves two real problems with the single-step flow:

1. **Workspace picker works.** OIDC triggers Slack's native workspace dropdown, so users with multiple workspaces can pick the right one.
2. **Non-installers can sign in.** A second engineer at a workspace where Firefight is already installed can sign into the dashboard without triggering the install flow (which would fail because they aren't an App Manager).

The product model is **Slack-native**: installation is the admin gate; any Slack workspace member who uses Firefight — via `/firefight`, a Slack interaction, a channel join, or OIDC sign-in on the dashboard — is auto-provisioned as a member. There is no invitation system and no per-workspace auto-provision flag. Roles (`member` / `admin` / `owner`) still exist on memberships for future admin-action gating, but basic access does not require explicit seat management.

### Stack

- **Backend**: Rails 8.1
- **Frontend**: React 19 + Inertia.js + TypeScript
- **OAuth**: Two OmniAuth strategies — `slack_openid` (identity) and `slack` (bot install)
- **Token refresh**: `RefreshSlackTokensJob` via Solid Queue, hourly
- **Storage**: PostgreSQL with UUID primary keys; bot/refresh tokens encrypted at rest

### Platforms

Currently Slack only. The schema is platform-agnostic (`workspaces.platform` enum supports `slack` and `teams`). Adding Teams later requires a new OmniAuth strategy and `Workspace.find_or_create_from_teams!` — no schema changes.

---

## Sign-in & Membership Decision Tree

After Slack OIDC returns identity:

```
Slack OIDC returns: { email, slack_user_id, team_id, team_name, name, image }
        ↓
Find Workspace by platform_id == team_id
├─ FOUND (Firefight is installed for this team)
│   ↓
│   Find WorkspaceMembership by (workspace, user)
│   ├─ FOUND     → Sign in. Dashboard.
│   └─ NOT FOUND → Auto-provision via WorkspaceMemberProvisioner, sign in.
│
└─ NOT FOUND (workspace doesn't exist)
    ↓
    "Firefight isn't installed for {team_name} yet" page.
    Buttons: [Install Firefight] (triggers bot OAuth — Slack rejects non-admins).
```

This logic lives in `SlackAuthenticationService#handle_openid_signin` and returns an `AuthOutcome` value object with two variants: `signed_in` or `install_needed`. The controller maps the outcome to an HTTP response — no decision logic lives in the controller.

---

## Two-Step Slack Auth Flow

### Step 1 — OIDC (identity)

```
User clicks "Sign in with Slack"
    ↓
GET /auth/slack_openid       (handled by OmniAuth middleware)
    ↓
Slack OIDC consent + workspace picker
    ↓
GET /auth/slack_openid/callback
    ↓
Auth::OmniauthCallbacksController#slack_openid
    ↓
SlackAuthenticationService#handle_openid_signin → AuthOutcome
    ↓
Controller dispatches based on outcome:
  - signed_in?      → set session, redirect to dashboard (or /onboarding/welcome on first install)
  - install_needed? → stash team in session, redirect to /onboarding/install
```

### Step 2 — Bot install (only when needed)

Only triggered when a workspace doesn't yet exist in our DB and the user opts to install. The OIDC step's `team_id` is stashed in `session[:pending_team_id]`, and the OmniAuth `setup` proc forwards it as `authorize_params[:team]`, which forces Slack to skip the picker on step 2.

```
User clicks "Add Firefight to Slack" on /onboarding/install
    ↓
GET /auth/slack              (uses session[:pending_team_id])
    ↓
Slack bot OAuth consent (bot scopes only — user identity came from step 1)
    ↓
GET /auth/slack/callback
    ↓
Auth::OmniauthCallbacksController#slack
    ↓
SlackAuthenticationService#handle_install(auth_hash, user: pending_user)
    → Workspace.process_slack_installation(auth_hash, user:)
    → SlackWorkspaceSetupWorkflow.start! (first install only)
    → AuthOutcome.signed_in(first_install: true)
    ↓
Set session, redirect to /onboarding/welcome
```

The install provider requests **bot scopes only**; user identity is carried by the prior OIDC step and threaded through via `session[:pending_user_id]`. The install callback never re-derives identity from the bot hash's `users.info` fetch (which is brittle and often returns partial data).

### Why two steps

| Concern | Single step (old) | Two step (current) |
|---|---|---|
| Workspace picker | Broken — `team: ""` ignored | Works natively via OIDC |
| Non-admin sign-in | Fails (Slack blocks bot install) | Works (OIDC carries identity) |
| Onboarding control | Permissions screen first | Show value prop, then ask for bot |
| Code complexity | One callback | Two callbacks (one is ~5 lines) |

---

## Membership Provisioning

A `WorkspaceMembership` is the billable unit. It can be created in three places — all converging on `WorkspaceMemberProvisioner.find_or_provision!` or the install-specific constructor.

### 1. Workspace install (owner)

The first user installs Firefight via bot OAuth (step 2). `Workspace.process_slack_installation` creates the workspace and the installer's membership with `role: owner`. Triggers `SlackWorkspaceSetupWorkflow`. This path is distinct from provisioner — it also needs to store the bot token on the workspace.

### 2. Slack-side usage (member)

When a Slack user touches Firefight via Slack — runs `/firefight`, clicks an interactive component, or is added to an incident channel — `WorkspaceMemberProvisioner.find_or_provision!` creates their membership with `role: member`. Wired in at the boundary layer:

- `ProcessCommandJob#ensure_member_provisioned` — for async slash commands
- `InteractionDispatcher.ensure_member_provisioned` — for synchronous button/modal interactions
- `Events::MemberJoinedChannelHandler` — for `member_joined_channel` events

Existing members are returned without a Slack API call; new members trigger one `users.info` fetch via the adapter.

### 3. Dashboard OIDC sign-in (member)

When someone signs in via OIDC and the workspace exists but they have no membership yet, `SlackAuthenticationService#handle_openid_signin` calls the same provisioner, passing the OIDC-provided profile (`auth_hash.info`) via the `user_profile:` kwarg so the adapter fetch is skipped — we already have name, email, avatar from the ID token.

This means a Slack workspace member who has never used Firefight in Slack can sign into the dashboard directly and will be provisioned as a member on first visit.

### Provisioner contract

```ruby
WorkspaceMemberProvisioner.find_or_provision!(
  workspace:,
  platform_user_id:,        # Slack user id (U...)
  adapter:,                 # used iff user_profile is not supplied
  user: nil,                # optional: pre-identified User
  user_profile: nil         # optional: hash with :real_name/:name/:email/etc.
)
```

Returns the existing or newly-created `WorkspaceMembership`. Returns `nil` on `AdapterError` (e.g., Slack API unavailable) — callers should tolerate nil.

---

## Architecture

### Layers

```
HTTP                   Auth::OmniauthCallbacksController (slim — 5 line actions)
                       OnboardingController (renders Inertia pages)
                            ↓
Decision logic         SlackAuthenticationService
                            ↓ returns
Value object           AuthOutcome (signed_in? / install_needed?)
                            ↓ used by
State changes          User.find_or_create_from_openid!
                       Workspace.process_slack_installation
                       WorkspaceMemberProvisioner.find_or_provision!
                            ↓
External               OmniAuth strategies (slack, slack_openid)
                       Slack::Client (via WorkspaceAdapter)
```

The controller has no case statement on raw symbols. It calls the service, gets an `AuthOutcome`, and dispatches via predicate methods. Session writes and redirects are the only HTTP concerns that stay in the controller.

### OmniAuth strategies

Two providers are registered in `config/initializers/omniauth.rb`:

- **`:slack_openid`** (`lib/omniauth/strategies/slack_openid.rb`) — sign-in flow. Hits `slack.com/oauth/v2/authorize` with `scope=` (empty) and `user_scope=openid,profile,email`. This is the same approach incident.io uses — Slack treats it as a sign-in flow, shows its native workspace picker + consent screen, and returns user identity only (no bot token).
- **`:slack`** (`lib/omniauth/strategies/slack.rb`) — OAuth v2 with **bot scopes only**. Setup proc reads `session[:pending_team_id]` and forwards it as `authorize_params[:team]` so step 2 skips the picker.

### Routes

```ruby
get  "/auth/slack_openid/callback", to: "auth/omniauth_callbacks#slack_openid", as: :slack_openid_callback
get  "/auth/slack/callback",        to: "auth/omniauth_callbacks#slack",        as: :slack_install_callback
get  "/auth/failure",               to: "auth/omniauth_callbacks#failure"

get "/onboarding/install", to: "onboarding#install", as: :onboarding_install
get "/onboarding/welcome", to: "onboarding#welcome", as: :onboarding_welcome

scope :app do
  # ... other app routes ...
  get "/settings/members", to: "settings#members", as: :settings_members
end
```

### Session keys

| Key | Set by | Cleared by |
|---|---|---|
| `user_id`, `workspace_id` | sign-in callback | logout |
| `pending_team_id`, `pending_team_name`, `pending_user_id` | OIDC callback when `install_needed?` | sign-in callback after install |
| `show_welcome_note` | install completion | welcome page render (consumed once) |

`apply_outcome` in the controller clears all `pending_*` keys on successful sign-in.

---

## Database Schema

### Tables

1. **`workspaces`** — Slack workspaces / teams.
2. **`users`** — Application users, identified by email.
3. **`workspace_memberships`** — Join table linking users to workspaces with a role.

### `workspaces`

```ruby
create_table :workspaces, id: :uuid do |t|
  t.string   :platform               # 'slack' or 'teams'
  t.string   :platform_id            # Slack team ID (e.g. T01234567)
  t.string   :name
  t.string   :avatar_url
  t.jsonb    :platform_data
  t.text     :access_token           # encrypted bot token
  t.text     :refresh_token          # encrypted
  t.datetime :token_expires_at
  t.datetime :installed_at
  t.timestamps
end
add_index :workspaces, [ :platform, :platform_id ], unique: true
```

### `users`

```ruby
create_table :users, id: :uuid do |t|
  t.string :email
  t.string :name
  t.string :avatar_url
  t.timestamps
end
add_index :users, :email, unique: true
```

`User.find_or_create_from_openid!(auth_hash)` is the OIDC constructor — sibling to `find_or_create_from_omniauth!` (used by the install path). The two paths produce different auth hash shapes, so they have separate constructors.

### `workspace_memberships`

```ruby
create_table :workspace_memberships, id: :uuid do |t|
  t.uuid     :user_id
  t.uuid     :workspace_id
  t.string   :platform_user_id       # Slack user ID
  t.string   :role                   # 'member' | 'admin' | 'owner'
  t.jsonb    :platform_data
  t.text     :access_token           # encrypted user token (install path only)
  t.text     :refresh_token          # encrypted
  t.datetime :token_expires_at
  t.datetime :joined_at
  t.timestamps
end
add_index :workspace_memberships, [ :workspace_id, :platform_user_id ], unique: true
```

Memberships created via the provisioner (OIDC sign-in and Slack-side usage) don't carry user tokens — only identity. Only the install path sets bot/user tokens.

---

## Configuration

### Secrets

Secrets resolve via **ENV first, Rails credentials as fallback**. The pattern in `config/initializers/omniauth.rb`:

```ruby
ENV["SLACK_CLIENT_ID"] || Rails.application.credentials.dig(:slack, :client_id)
```

In production, secrets come from the Kamal `.env` (sourced from 1Password). In local development, secrets come from the `.env` file (copy from `.env.example`).

### Required env vars

| Variable | Purpose |
|---|---|
| `SLACK_CLIENT_ID` | OAuth + token refresh |
| `SLACK_CLIENT_SECRET` | OAuth + token refresh |
| `SLACK_SIGNING_SECRET` | Webhook signature verification |

### Slack manifests

Scopes are defined in `config/slack_manifests/{development,production}.yml` and read into the OAuth strategies via `Slack::ManifestReader.scopes_for_environment(Rails.env)`.

OIDC user scopes (required for the workspace picker) + bot scopes:
```yaml
oauth_config:
  scopes:
    user:
      - openid
      - profile
      - email
      - users:read
      - users:read.email
    bot:
      - team:read
      - commands
      - chat:write
      # ... etc
```

The `:slack` install provider uses `bot` scopes only — the `user` block maps to the Slack app's OIDC configuration and is consumed by the `:slack_openid` provider at sign-in. When manifest scopes change, re-upload the manifest to api.slack.com → app dashboard. Existing installations need to re-authorize for new bot scopes; OIDC scopes apply to new sign-ins automatically.

### Rails Active Record encryption

Bot/user tokens (`Workspace#access_token`, `Workspace#refresh_token`, `WorkspaceMembership#access_token`, `WorkspaceMembership#refresh_token`) are encrypted via Rails' `encrypts`. Keys live in Rails credentials under `active_record_encryption.{primary_key, deterministic_key, key_derivation_salt}`. Generate with `bin/rails db:encryption:init` and paste into the credentials file.

`RAILS_MASTER_KEY` decrypts credentials. In production it's set on the Kamal host via `.env`.

---

## Token Management

Bot and user tokens expire after 12 hours (Slack token rotation). `RefreshSlackTokensJob` runs hourly via Solid Queue and refreshes anything expiring in the next 3 hours.

```ruby
service = Slack::TokenRefreshService.new
service.refresh_workspace(workspace)
service.refresh_membership(membership)
service.refresh_all_expiring(buffer: 3.hours)
```

Rake tasks for manual operations (use shell quotes — brackets):
```bash
bin/rails slack:list_workspaces
bin/rails "slack:refresh_workspace[uuid]"
bin/rails "slack:refresh_membership[uuid]"
bin/rails slack:refresh_all_expiring
bin/rails slack:force_refresh_all_workspaces
```

Recurring schedule lives in `config/recurring.yml`. Worker starts via `bin/jobs` (`bin/dev` in development, `kamal app exec` or the worker container in production).

---

## Local Development

1. **Create a Slack app** from `config/slack_manifests/development.yml`.
   - https://api.slack.com/apps → Create New App → From an app manifest

2. **Set env vars** by copying `.env.example` to `.env` and filling in:
   ```
   SLACK_CLIENT_ID=...
   SLACK_CLIENT_SECRET=...
   SLACK_SIGNING_SECRET=...
   ```

3. **Generate AR encryption keys** (one-time, only if not already in credentials):
   ```bash
   bin/rails db:encryption:init
   EDITOR=nvim bin/rails credentials:edit
   ```
   Paste the generated `active_record_encryption:` block.

4. **Migrate**:
   ```bash
   bin/rails db:migrate
   ```

5. **Run**:
   ```bash
   bin/dev
   ```

6. **Sign in**: visit http://localhost:3000, click "Continue with Slack". Slack should show the workspace picker (this is OIDC working). Pick a workspace where Firefight isn't installed → land on `/onboarding/install` → click "Add Firefight to Slack" → bot install completes → `/onboarding/welcome`.

### Helpers in controllers

```ruby
current_user           # User instance or nil
current_workspace      # Workspace instance or nil
user_signed_in?
require_authentication # before_action
```

### Helpers in Inertia frontend

```tsx
import { usePage } from "@inertiajs/react";
import { SharedProps } from "@/types";

const { currentUser, currentWorkspace } = usePage<SharedProps>().props;
```

---

## Deployment

Production runs on **Hetzner** (app on Cloud VPS, Postgres on Dedicated) deployed via **Kamal**. Infrastructure is managed in Terraform.

- App secrets are set via Kamal `.env` (sourced from 1Password). ENV takes precedence over `Rails.application.credentials`, so credential files are optional in production.
- `RAILS_MASTER_KEY` is required (decrypts AR encryption keys for token storage).
- Postgres backups via pgbackrest to Cloudflare R2.

### Production callback URLs

The Slack production app must list both callbacks:
```yaml
oauth_config:
  redirect_urls:
    - https://app.firefight.app/auth/slack/callback
    - https://app.firefight.app/auth/slack_openid/callback
```

Slack webhook URLs (commands, events, interactions) point at `https://slack.firefight.app/api/v1/...` — see manifest.

---

## Troubleshooting

### OIDC returns but workspace picker doesn't appear

Slack only shows the picker when the user has multiple workspaces in the same browser session AND the OIDC scopes include `openid`. Verify the manifest has `openid`, `profile`, `email` under `oauth_config.scopes.user` and that the manifest has been re-uploaded to api.slack.com.

### "Firefight isn't installed" when it actually is

Workspace lookup is by `(platform: :slack, platform_id: team_id)`. If a workspace was installed under a different Slack app (e.g. dev vs prod), the `platform_id` will match but you'll be hitting a different DB. Confirm Slack app + Rails env line up.

### Install completes but welcome page bounces

`/onboarding/welcome` requires `session[:user_id]`. The install callback sets it, but if session cookies are blocked or the OmniAuth callback raised an exception mid-transaction, the sign-in writes don't land. Check `log/development.log` for `auth.slack_install_failed` entries.

### Token refresh fails

```ruby
workspace = Workspace.find_by(name: "Acme")
workspace.refresh_token.present?
workspace.token_expires_at
Slack::TokenRefreshService.new.refresh_workspace(workspace)
```

If Slack returns `invalid_grant`: the app was uninstalled from the workspace, the client secret rotated, or token rotation isn't enabled in the Slack app dashboard.

### Missing Active Record encryption credential

```bash
bin/rails db:encryption:init
EDITOR=nvim bin/rails credentials:edit
# paste active_record_encryption: block
```
Restart the server.

### Promote a member to owner

```ruby
membership = WorkspaceMembership.find_by(user: user, workspace: workspace)
membership.update!(role: "owner")
```

---

## Future Work

### RBAC enforcement

Memberships have a `role` column (`member` / `admin` / `owner`) but no controller-level enforcement yet. Authorization is currently coarse — sign-in alone gates the dashboard. Adding RBAC means:
- Permission checks in Inertia controllers (e.g. only owner/admin can access certain settings pages).
- Permission checks in API controllers via the existing `authorize!(resource, action)` pattern in `ApiAuthentication`.

### Workspace switcher

Users with multiple memberships can't switch workspaces in the UI yet. Dashboard pulls from `session[:workspace_id]`. The data model already supports it (`user.workspaces` returns all).

### Microsoft Teams

Schema is ready — `workspaces.platform` enum supports `:teams`. Adding Teams requires:
- New OmniAuth strategy in `lib/omniauth/strategies/teams.rb`.
- `Workspace.find_or_create_from_teams!` constructor.
- Teams adapter under `app/adapters/teams/`.
- Teams manifest in `config/teams_manifests/`.
- `WorkspaceAdapter.for(workspace)` factory already dispatches by platform.

---

## API Reference

### Models

```ruby
# User
User.find_or_create_from_omniauth!(auth_hash)   # install path (OAuth v2 hash)
User.find_or_create_from_openid!(auth_hash)     # OIDC path (different hash shape)
user.workspaces / user.workspace_memberships
user.member_of?(workspace) / .owner_of?(workspace) / .admin_of?(workspace)

# Workspace
Workspace.find_or_create_from_slack!(auth_hash)
Workspace.process_slack_installation(auth_hash, user: nil) # transactional: workspace + user + membership
workspace.token_expired?
workspace.adapter                                # WorkspaceAdapter.for(self)

# WorkspaceMembership
WorkspaceMembership.find_or_create_from_omniauth!(user, workspace, auth_hash)
membership.member_role? / .admin_role? / .owner_role?
```

### Services

```ruby
SlackAuthenticationService.new
  .handle_openid_signin(auth_hash)                    # → AuthOutcome
  .handle_install(auth_hash, user: nil)               # → AuthOutcome
  .process_oauth_callback(auth_hash)                  # legacy, returns Hash

WorkspaceMemberProvisioner
  .find_or_provision!(workspace:, platform_user_id:, adapter:, user: nil, user_profile: nil)

Slack::TokenRefreshService.new
  .refresh_workspace(workspace) / .refresh_membership(membership)
  .refresh_all_expiring(buffer: 3.hours)
```

### Value object

```ruby
AuthOutcome.signed_in(membership:, message:, first_install: false)
AuthOutcome.install_needed(user:, team_id:, team_name:)

outcome.signed_in? / .install_needed? / .first_install?
outcome.membership / .user / .team_id / .team_name / .message
```

### Rake tasks

```bash
bin/rails slack:list_workspaces
bin/rails "slack:refresh_workspace[uuid]"
bin/rails "slack:refresh_membership[uuid]"
bin/rails slack:refresh_all_expiring
bin/rails slack:force_refresh_all_workspaces
```

---

## Security

- Bot and user tokens encrypted at rest via Rails `encrypts`.
- Sessions are encrypted, HTTP-only, secure in production.
- OmniAuth CSRF protection enabled; failures redirect to `/auth/failure`.
- Install access is gated by Slack itself — only a workspace admin can approve the bot OAuth consent, which is Firefight's only admin-level gate. Anyone with access to the Slack workspace after install is considered a member; if an organization needs finer-grained dashboard access control, remove the user from the Slack workspace.

---

## Resources

- [Slack OAuth v2](https://api.slack.com/authentication/oauth-v2)
- [Slack OpenID Connect](https://api.slack.com/authentication/sign-in-with-slack)
- [Slack token rotation](https://api.slack.com/authentication/rotation)
- [OmniAuth](https://github.com/omniauth/omniauth)
- Internal: `lib/omniauth/strategies/{slack,slack_openid}.rb`, `app/services/slack_authentication_service.rb`, `app/services/workspace_member_provisioner.rb`, `app/models/auth_outcome.rb`
