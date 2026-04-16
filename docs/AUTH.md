# Authentication

## Table of Contents
- [Overview](#overview)
- [Sign-in & Membership Decision Tree](#sign-in--membership-decision-tree)
- [Two-Step Slack Auth Flow](#two-step-slack-auth-flow)
- [Three Paths to Membership](#three-paths-to-membership)
- [Invitations](#invitations)
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

1. **Workspace picker works.** OIDC triggers Slack's native workspace dropdown, so users with multiple workspaces can pick the right one. The previous `team: ""` hack didn't work — Slack still defaulted to the user's active workspace cookie.
2. **Non-installers can sign in.** A second engineer at a workspace where Firefight is already installed can sign into the dashboard without triggering the install flow (which would fail because they aren't an App Manager).

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
│   ├─ FOUND → Sign in. Dashboard.
│   │         (Member was already provisioned via install,
│   │          bot interaction, prior invite, or auto-provision.)
│   │
│   └─ NOT FOUND
│       ↓
│       Pending invitation in session for (workspace, email)?
│       ├─ YES → Consume invite, create membership, sign in.
│       └─ NO
│           ↓
│           workspace.allow_auto_provision?  (default false)
│           ├─ TRUE  → Auto-create membership, sign in.
│           └─ FALSE → "Ask your admin for an invite" page.
│
└─ NOT FOUND (workspace doesn't exist)
    ↓
    "Firefight isn't installed for {team_name} yet" page.
    Buttons: [Install Firefight] (triggers bot OAuth — Slack rejects non-admins).
```

This logic lives in `SlackAuthenticationService#handle_openid_signin` and returns an `AuthOutcome` value object. The controller maps the outcome to an HTTP response — no decision logic lives in the controller.

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
  - signed_in?      → set session, redirect to dashboard
  - install_needed? → stash team in session, redirect to /onboarding/install
  - invite_needed?  → redirect to /onboarding/needs_invite
```

### Step 2 — Bot install (only when needed)

Only triggered when a workspace doesn't yet exist in our DB and the user opts to install. The OIDC step's `team_id` is stashed in `session[:pending_team_id]`, and the OmniAuth `setup` proc forwards it as `authorize_params[:team]`, which forces Slack to skip the picker on step 2.

```
User clicks "Add Firefight to Slack" on /onboarding/install
    ↓
GET /auth/slack              (uses session[:pending_team_id])
    ↓
Slack bot OAuth consent
    ↓
GET /auth/slack/callback
    ↓
Auth::OmniauthCallbacksController#slack
    ↓
SlackAuthenticationService#handle_install
    → Workspace.process_slack_installation(auth_hash)
    → SlackWorkspaceSetupWorkflow.start! (first install only)
    → AuthOutcome.signed_in
    ↓
Set session, redirect to dashboard
```

### Why two steps

| Concern | Single step (old) | Two step (current) |
|---|---|---|
| Workspace picker | Broken — `team: ""` ignored | Works natively via OIDC |
| Non-admin sign-in | Fails (Slack blocks bot install) | Works (OIDC carries identity) |
| Onboarding control | Permissions screen first | Show value prop, then ask for bot |
| Code complexity | One callback | Two callbacks (one is ~5 lines) |

---

## Three Paths to Membership

A `WorkspaceMembership` is the billable unit. It can be created three ways. Sign-in just checks whether one exists.

### 1. Workspace install (owner)

The first user installs Firefight via bot OAuth (step 2). `Workspace.process_slack_installation` creates the workspace and the installer's membership with `role: owner`. Triggers `SlackWorkspaceSetupWorkflow`.

### 2. Bot-interaction provisioning (implicit consent)

When a Slack user touches Firefight via Slack — runs `/firefight`, clicks an interaction, or is added to an incident channel — `WorkspaceMemberProvisioner.find_or_provision!` creates their membership with `role: member`. Wired into `CommandDispatcher` and `InteractionDispatcher` at the top of `dispatch`.

The idea: they've already used the product, so they should be able to sign into the dashboard with no additional friction. By the time they visit `app.firefight.app`, OIDC sign-in finds an existing membership and just logs them in.

### 3. Explicit invitation (admin)

An admin invites an email from settings. The recipient gets a magic-link email. Clicking the link stores the invitation ID in the session and bounces them through OIDC. On callback, the pending invitation is consumed and a membership is created. See [Invitations](#invitations) below.

### Optional 4th path — `allow_auto_provision`

A workspace owner can flip `workspaces.allow_auto_provision = true`. Anyone whose Slack identity matches the team can then sign in with no invite. Off by default — exposes seat billing and external-guest risk.

---

## Invitations

### Lifecycle

```
Admin opens Settings → Members → Invite
    ↓
POST /app/settings/invitations { email }
    ↓
Invitation row created (expires 7 days from now)
    ↓
InvitationMailer#invite delivers magic link
    Link: /invitations/:signed_id
    signed_id is a Rails-signed token with purpose: :workspace_invite
    ↓
Recipient clicks link
    ↓
GET /invitations/:signed_id
    → InvitationsController#show
    → verifies signed_id, checks active scope (not redeemed, not expired)
    → stores invitation.id in session[:pending_invitation_id]
    → redirects to /auth/slack_openid
    ↓
OIDC flow returns
    ↓
SlackAuthenticationService#handle_openid_signin
    → finds pending invitation by id
    → guards: invitation must belong to the OIDC team_id's workspace AND match email
    → calls Invitation#consume! which creates the membership and sets redeemed_at
    ↓
Sign in, dashboard
```

### Model rules

- One active (un-redeemed, un-expired) invitation per `(workspace_id, email)` — partial uniqueness via `conditions: -> { where(redeemed_at: nil) }`.
- `Invitation::DEFAULT_TTL = 7.days` set in `before_validation :set_default_expiry, on: :create`.
- `consume!` runs in a transaction — calls `workspace.auto_provision_member!` and updates `redeemed_at` + `redeemed_by`.
- Admins can revoke before redemption (`DELETE /app/settings/invitations/:id`).

### No `role` column

We don't yet have RBAC enforcement (no controller-level permission checks beyond owner/admin presence on the membership record). Invitations don't carry a role — every consumed invitation produces a `role: member` membership via `Workspace#auto_provision_member!`. When RBAC lands, add a `role` column and pass it through.

---

## Architecture

### Layers

```
HTTP                   Auth::OmniauthCallbacksController (slim — 5 line actions)
                       InvitationsController (signed_id lookup → session → redirect)
                       OnboardingController (renders Inertia pages)
                            ↓
Decision logic         SlackAuthenticationService
                            ↓ returns
Value object           AuthOutcome (signed_in? / install_needed? / invite_needed?)
                            ↓ used by
State changes          User.find_or_create_from_openid!
                       Workspace.process_slack_installation
                       Workspace#auto_provision_member!
                       Invitation#consume!
                       WorkspaceMemberProvisioner.find_or_provision!
                            ↓
External               OmniAuth strategies (slack, slack_openid)
                       Slack::Client (via WorkspaceAdapter)
```

The controller has no case statement on raw symbols. It calls the service, gets an `AuthOutcome`, and dispatches via predicate methods. Session writes and redirects are the only HTTP concerns that stay in the controller.

### OmniAuth strategies

Two providers are registered in `config/initializers/omniauth.rb`:

- **`:slack_openid`** (`lib/omniauth/strategies/slack_openid.rb`) — sign-in flow. Hits `slack.com/oauth/v2/authorize` with `scope=` (empty) and `user_scope=openid,profile,email`. This is the same approach incident.io uses — Slack treats it as a sign-in flow, shows its native workspace picker + consent screen, and returns user identity only (no bot token). The standalone `/openid/connect/authorize` endpoint does **not** show a workspace picker reliably and was the wrong choice initially.
- **`:slack`** (`lib/omniauth/strategies/slack.rb`) — OAuth v2 with bot scopes. Setup proc reads `session[:pending_team_id]` and forwards it as `authorize_params[:team]` so step 2 skips the picker.

The previous `team: ""` hack on `:slack` is gone — it never worked.

### Routes

```ruby
get  "/auth/slack_openid/callback", to: "auth/omniauth_callbacks#slack_openid", as: :slack_openid_callback
get  "/auth/slack/callback",        to: "auth/omniauth_callbacks#slack",        as: :slack_install_callback
get  "/auth/failure",               to: "auth/omniauth_callbacks#failure"

resources :invitations, only: [ :show ], param: :signed_id

get "/onboarding/install",      to: "onboarding#install",      as: :onboarding_install
get "/onboarding/needs_invite", to: "onboarding#needs_invite", as: :onboarding_needs_invite

scope :app do
  # ... other app routes ...
  get "/settings/members", to: "settings#members", as: :settings_members
  resources :invitations, only: [ :create, :destroy ], path: "settings/invitations"
end
```

### Session keys

| Key | Set by | Cleared by |
|---|---|---|
| `user_id`, `workspace_id` | sign-in callback | logout |
| `pending_team_id`, `pending_team_name`, `pending_user_id` | OIDC callback when `install_needed?` | sign-in callback after install |
| `pending_invitation_id` | InvitationsController#show | sign-in callback after invite consumed |

`apply_outcome` in the controller clears all `pending_*` keys on successful sign-in.

---

## Database Schema

### Tables

1. **`workspaces`** — Slack workspaces / teams.
2. **`users`** — Application users, identified by email.
3. **`workspace_memberships`** — Join table linking users to workspaces with a role.
4. **`invitations`** — Pending and historical workspace invites.

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
  t.boolean  :allow_auto_provision, null: false, default: false
  t.timestamps
end
add_index :workspaces, [ :platform, :platform_id ], unique: true
```

`allow_auto_provision` enables [path 4](#optional-4th-path--allow_auto_provision) above. Default false.

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

Memberships created via OIDC paths (invite, auto-provision, bot-interaction) don't carry user tokens — only identity. Only the install path sets bot/user tokens.

### `invitations`

```ruby
create_table :invitations, id: :uuid do |t|
  t.references :workspace,    type: :uuid, null: false, foreign_key: true
  t.references :invited_by,   type: :uuid, null: false, foreign_key: { to_table: :workspace_memberships }
  t.string     :email,        null: false
  t.datetime   :expires_at,   null: false
  t.datetime   :redeemed_at
  t.references :redeemed_by,  type: :uuid, foreign_key: { to_table: :workspace_memberships }
  t.timestamps
end
add_index :invitations, [ :workspace_id, :email ]
```

Email uniqueness is enforced at the model layer via a partial uniqueness constraint scoped to active (un-redeemed) invitations. No `role` column — see [Invitations](#invitations).

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

OIDC user scopes (required for the workspace picker):
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

When manifest scopes change, re-upload the manifest to api.slack.com → app dashboard. Existing installations need to re-authorize for new bot scopes; OIDC scopes apply to new sign-ins automatically.

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

6. **Sign in**: visit http://localhost:3000, click "Continue with Slack". Slack should show the workspace picker (this is OIDC working). Pick a workspace where Firefight isn't installed → land on `/onboarding/install` → click "Add Firefight to Slack" → bot install completes → dashboard.

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

### Staging

There is no staging environment currently. Both `config/slack_manifests/development.yml` and `config/slack_manifests/production.yml` are in use; staging-related references in older infra docs are out of date.

---

## Troubleshooting

### OIDC returns but workspace picker doesn't appear

Slack only shows the picker when the user has multiple workspaces in the same browser session AND the OIDC scopes include `openid`. Verify the manifest has `openid`, `profile`, `email` under `oauth_config.scopes.user` and that the manifest has been re-uploaded to api.slack.com.

### "Firefight isn't installed" when it actually is

Workspace lookup is by `(platform: :slack, platform_id: team_id)`. If a workspace was installed under a different Slack app (e.g. dev vs prod), the `platform_id` will match but you'll be hitting a different DB. Confirm Slack app + Rails env line up.

### Magic-link invitation 404s

`InvitationsController#show` uses `Invitation.find_signed(params[:signed_id], purpose: :workspace_invite)`. Common causes:
- Link is older than `Invitation::DEFAULT_TTL` (7 days).
- Invitation was already redeemed (`redeemed_at` set) — `Invitation.active` excludes it.
- Invitation was revoked (deleted) by the admin.

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
- Permission checks in Inertia controllers (e.g. only owner/admin can access `/app/settings/invitations`).
- A `role` column on `Invitation` so admins can set the recipient's role at invite time.
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

### Cross-workspace invitation links

Currently invitations are scoped to a single workspace + email. A "share invite link" feature would generate a token that any signed-in user can redeem against a specific workspace.

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
Workspace.process_slack_installation(auth_hash) # transactional: workspace + user + membership
workspace.auto_provision_member!(user:, auth_hash:) # OIDC path member creation
workspace.allow_auto_provision?
workspace.token_expired?
workspace.adapter                                # WorkspaceAdapter.for(self)

# WorkspaceMembership
WorkspaceMembership.find_or_create_from_omniauth!(user, workspace, auth_hash)
membership.member_role? / .admin_role? / .owner_role?

# Invitation
Invitation::DEFAULT_TTL
Invitation.active / .pending / .redeemed
invitation.consume!(user:, auth_hash:)           # creates membership, marks redeemed
invitation.signed_id(expires_in:, purpose: :workspace_invite)
```

### Services

```ruby
SlackAuthenticationService.new
  .handle_openid_signin(auth_hash, pending_invitation_id: nil) # → AuthOutcome
  .handle_install(auth_hash)                                   # → AuthOutcome
  .process_oauth_callback(auth_hash)                           # legacy, returns Hash

WorkspaceMemberProvisioner
  .find_or_provision!(workspace:, platform_user_id:, adapter:) # bot-interaction path

Slack::TokenRefreshService.new
  .refresh_workspace(workspace) / .refresh_membership(membership)
  .refresh_all_expiring(buffer: 3.hours)
```

### Value object

```ruby
AuthOutcome.signed_in(membership:, message:)
AuthOutcome.install_needed(user:, team_id:, team_name:)
AuthOutcome.invite_needed(team_name:)

outcome.signed_in? / .install_needed? / .invite_needed?
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
- Magic-link invitations use Rails `signed_id` with explicit `purpose: :workspace_invite` — tampered links and cross-purpose tokens are rejected cryptographically before any DB lookup.
- Invitation consumption double-checks: signed_id valid AND record is in `active` scope (not redeemed, not expired) AND email matches the OIDC identity AND workspace matches the OIDC team_id.
- Sessions are encrypted, HTTP-only, secure in production.
- OmniAuth CSRF protection enabled; failures redirect to `/auth/failure`.

---

## Resources

- [Slack OAuth v2](https://api.slack.com/authentication/oauth-v2)
- [Slack OpenID Connect](https://api.slack.com/authentication/sign-in-with-slack)
- [Slack token rotation](https://api.slack.com/authentication/rotation)
- [OmniAuth](https://github.com/omniauth/omniauth)
- Internal: `lib/omniauth/strategies/{slack,slack_openid}.rb`, `app/services/slack_authentication_service.rb`, `app/models/{auth_outcome,invitation}.rb`
