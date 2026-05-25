# Platform Adapter Contract

This document specifies what a new platform adapter must implement to plug
into Firefight, and what existing assumptions in the codebase need to bend
to accommodate it. It is the answer to "we want to add Microsoft Teams /
Mattermost / etc. — what's the actual work?"

The contract is split into three layers:

1. **Adapter contract** (this directory, `app/adapters/<platform>/`) —
   programmatic surface that services and workflows depend on.
2. **Entry points** (controllers, dispatchers, handlers, normalizers) —
   platform-specific. New platforms add their own; existing Slack ones are
   not touched.
3. **Domain model** (`Incident`, `WorkspaceMembership`, etc.) — currently
   carries Slack-shaped fields. Section [Domain-model leaks](#domain-model-leaks)
   describes the gaps a second platform exposes.

---

## Adapter contract

Every platform adapter inherits from `PlatformAdapter` and must implement
the methods below. Method bodies must rescue platform-specific errors and
re-raise as `AdapterError` subclasses (see
[Error translation](#error-translation)).

### Vocabulary

| Term | Definition |
|---|---|
| `channel_id` | Opaque platform-specific conversation identifier |
| `message_id` | Opaque platform-specific message identifier |
| `parent_message_id` | The message identifier a threaded reply hangs off of |
| `user_id` | Opaque platform-specific user identifier |
| `view` | Platform-specific modal/form descriptor — Block Kit hash for Slack, Adaptive Card JSON for Teams, Interactive Dialog hash for Mattermost. Adapter callers obtain a `view` from the platform's own `Modals::X.build` / `Forms::X.build` modules; the low-level adapter just hands it to the platform. |

### Channel operations

| Method | Returns |
|---|---|
| `create_channel(name:, is_private:)` | `{channel_id:, channel_name:}` |
| `archive_channel(channel_id:)` | `{success: true}` |
| `unarchive_channel(channel_id:)` | `{success: true}` |
| `set_channel_topic(channel_id:, topic:)` | `{success: true}` |
| `set_channel_metadata(channel_id:, topic:, purpose:)` | `{success: true}` |
| `invite_user(channel_id:, user_id:)` | `{invited_user:}` |
| `invite_users(channel_id:, user_ids:)` | `{invited_users:}` |

### Messaging

| Method | Returns |
|---|---|
| `post_message(channel_id:, text:, blocks:)` | `{message_id:}` |
| `post_threaded_message(channel_id:, parent_message_id:, text:, blocks:)` | `{message_id:}` |
| `post_ephemeral(channel_id:, user_id:, text:, blocks:)` | `{success: true}` |
| `update_message(channel_id:, message_id:, text:, blocks:)` | `{success: true}` |
| `delete_message(channel_id:, message_id:)` | `{success: true}` |
| `add_reaction(channel_id:, message_id:, name:)` | `{success: true}` |
| `pin_message(channel_id:, message_id:)` | `{ok: true}` |
| `get_message_permalink(channel_id:, message_id:)` | `{permalink:}` |
| `fetch_message(channel_id:, message_id:)` | `{message_id:, channel_id:, user_id:, text:, posted_at:, raw:}` |

### Modals / forms

| Method | Returns |
|---|---|
| `open_modal(trigger_id:, view:)` | `{success: true}` |
| `push_modal(trigger_id:, view:)` | `{success: true}` |

### Users / directory

| Method | Returns |
|---|---|
| `get_user_info(user_id:)` | `{user_id:, display_name:, real_name:, avatar_url:, email:, timezone:, raw:}` |
| `list_members` | `[{id:, name:, avatarUrl:}]` |
| `list_channels` | `[{id:, name:}]` |

### Error translation

Platform-specific errors must be caught inside each adapter method and
re-raised as a member of the `AdapterError` hierarchy:

```
AdapterError
├── TriggerExpired       — modal trigger / interaction token expired
├── ChannelExists        — channel name collision on create
├── AlreadyArchived      — archive on already-archived channel
├── NotFound             — channel/message/user not found
└── AlreadyInChannel     — invite of already-present user
```

Services / handlers rescue these AdapterError subclasses, never
platform-specific errors. Use `Slack::WorkspaceAdapter#translate_errors` as
a template.

---

## Domain-model leaks

These are places the database schema assumes Slack's data model. Each new
platform will hit at least one of them.

### `incident.channel_id` — single-column conversation reference

- **Slack** ✓ — single conversation ID (`C12345678`) addresses everything.
- **Mattermost** ✓ — single 26-char channel ID is globally unique.
- **Teams** ✗ — every Microsoft Graph call to a channel requires
  `(team_id, channel_id)` together. A Teams adapter needs an
  `incident.platform_team_id` column, or a composite encoding. Bot
  Framework's `conversation.id` does encode the team in some flows but is
  not stable for use as a stored reference.

**Fix when Teams arrives:** add nullable `incident.platform_team_id`; rename
`channel_id` → `platform_channel_id` for symmetry.

### `incident.initial_message_ts`, `incident.announcement_message_ts`

- **Slack** ✓ — `ts` is the message ID; column name leaks Slack vocab but
  the value is opaque.
- **Mattermost** ✓ — 26-char post ID, store as a string.
- **Teams** ⚠ — message IDs (`1648741500652`-style) are only unique within a
  channel. Reading/updating requires `(team_id, channel_id, message_id)`.
  Same tuple as for the channel reference, so no new column — but the
  column name is misleading. Rename `*_message_ts` → `*_message_id` for
  honesty.

### Threading model

- **Slack** ✓ — flat: any message can be a thread parent (`parent_message_id`).
- **Mattermost** ✓ — flat: replies use `root_id`, same model.
- **Teams** ⚠ — every top-level channel post starts a thread; replies live
  at `/messages/{root}/replies/{reply}` and are *not* first-class messages.
  You cannot reply to a reply.
  - For Firefight today: announcement-thread replies are the only threaded
    use case. Teams supports this 1:1 with Slack's pattern (post to channel
    → store `announcement_message_id` → reply via thread).
  - The "post a status update as a thread reply on the announcement" flow
    works identically. No model change needed for current features.

### `workspace_membership.platform_user_id`

- **Slack** ✓ — `U12345678`.
- **Mattermost** ✓ — 26-char user ID.
- **Teams** ✓ — Azure AD user ID (GUID), fits a `String` column. No change.

### Modal `view:` parameter

`open_modal(view:)` accepts whatever the platform's `Modals::X.build`
produced. Each platform's modal modules live in
`app/adapters/<platform>/modals/` (Slack: Block Kit; Teams: Adaptive Card;
Mattermost: interactive dialog hash). Callers in platform-specific entry
points (handlers/controllers) construct via the right module and hand the
opaque hash to the adapter.

No abstract "view spec" needs to exist. Each platform's call site already
knows which platform it's in.

---

## Per-platform implementation notes

### Slack (implemented)

`app/adapters/slack/`. Reference implementation.

### Mattermost (estimated cost: ~1-2 weeks)

**Direct port.** Mattermost's data model matches Slack's:

- Channel ID: single 26-char string. ✓
- Post ID: single 26-char string. ✓
- Threading via `root_id`. ✓
- `POST /api/v4/channels` to create channels via bot. ✓
- `POST /api/v4/posts/{id}/pin` to pin. ✓
- `POST /api/v4/reactions` for emoji reactions. ✓
- `POST /api/v4/actions/dialogs/open` for interactive dialogs (modals). ✓
  Uses `trigger_id` like Slack.

**No domain-model changes required.** Drop in a `Mattermost::WorkspaceAdapter`
inheriting `PlatformAdapter`, write the corresponding entry points
(`Mattermost::CommandAdapter`, `Mattermost::InteractionNormalizer`,
`Mattermost::SignatureVerifier`), and write the dialog/form modules in
`app/adapters/mattermost/dialogs/`.

API ref: [Mattermost API docs](https://developers.mattermost.com/api-documentation/),
[Interactive Dialogs](https://developers.mattermost.com/integrate/plugins/interactive-dialogs/).

### Microsoft Teams (estimated cost: ~4-6 weeks)

**Non-trivial port.** Multiple structural deltas:

1. **Add `incident.platform_team_id` column** (nullable). Teams channels are
   addressed as `(team_id, channel_id)`. Migrate existing Slack incidents
   to NULL; Teams adapter writes the team GUID on create.

2. **Rename `*_message_ts` columns → `*_message_id`** for honesty (also
   doubles as a Slack column-name cleanup).

3. **`pin_message` is unsupported on channels.** Microsoft Graph's
   `chats/{chatId}/pinnedMessages` only applies to chats, not channels. The
   Teams adapter's `pin_message` should be a no-op + log warning. Audit
   callers and confirm pin failure isn't load-bearing for UX (currently
   only `incident_creation_service#post_quick_actions_message` pins;
   incident still functions without it).

4. **No channel-level ephemeral messages.** Workarounds: per-user
   targeted Adaptive Card refresh, or fall back to DM. Document and accept
   minor UX divergence.

5. **Modals use Adaptive Cards** (called "Dialogs" / formerly "Task
   Modules"). Different JSON shape from Block Kit. Build a complete set of
   modal modules at `app/adapters/teams/modals/`. The bot invoke flow
   (`task/fetch` → return TaskInfo with adaptive card → `task/submit`) maps
   onto the existing `Interaction` POJO with no new boundaries.

6. **OAuth/install flow differs** — Azure AD app registration, bot
   manifest, tenant-scoped install. New work, but contained.

API refs: [Teams conversation basics](https://learn.microsoft.com/en-us/microsoftteams/platform/bots/how-to/conversations/conversation-basics),
[Graph: send chatMessage in channel](https://learn.microsoft.com/en-us/graph/api/chatmessage-post?view=graph-rest-1.0),
[Graph: create channel](https://learn.microsoft.com/en-us/graph/api/channel-post?view=graph-rest-1.0),
[Teams dialogs from bots](https://learn.microsoft.com/en-us/microsoftteams/platform/task-modules-and-cards/task-modules/task-modules-bots).

---

## What is NOT part of the adapter contract

These belong to platform-specific entry-point code, not the abstract
adapter:

- Webhook signature verification (`Slack::SignatureVerifier`, etc.)
- OAuth installation flow (`OAuthController`'s Slack-specific routes)
- Platform-specific event handlers (`Events::*` for Slack today)
- Command/interaction payload normalizers (`CommandAdapter`,
  `InteractionNormalizer`) — there's a `CommandAdapter` base; an
  `InteractionNormalizer` base does not exist yet but should follow the
  same pattern when a second platform arrives.
- Token management (`Slack::TokenManager`)
- Modal/message JSON builders under `app/adapters/<platform>/modals/` and
  `app/adapters/<platform>/messages/`

A new platform freely structures these as it sees fit, as long as the
final output is a `Command` or `Interaction` POJO carrying `platform: "X"`.

---

## Quick checklist for adding a new platform

1. Add the platform constant to `Platforms` (`app/models/platforms.rb`).
2. Implement `<Platform>::WorkspaceAdapter < PlatformAdapter` with every
   method in [Adapter contract](#adapter-contract). Use
   `translate_errors` to map platform errors into `AdapterError`.
3. Build modal modules under `app/adapters/<platform>/modals/` and
   message modules under `app/adapters/<platform>/messages/`. Mirror the
   Slack module organization for consistency.
4. Write `<Platform>::CommandAdapter < CommandAdapter` and
   `<Platform>::InteractionNormalizer` to convert raw webhook payloads
   into `Command` / `Interaction` POJOs.
5. Add platform-specific controllers under `app/controllers/api/v1/` for
   webhook ingestion, signature verification, and OAuth callbacks.
6. Add the platform to `WorkspaceAdapter.for(workspace)`'s factory dispatch.
7. Address the domain-model leaks ([Domain-model leaks](#domain-model-leaks))
   if the new platform requires them. Mattermost requires none. Teams
   requires the `platform_team_id` column and the `*_message_ts` →
   `*_message_id` rename.
8. Audit Slack-specific assumptions in `IncidentLifecycleService`,
   `IncidentCreationService`, `IncidentUpdateService` — none should need
   changes once the adapter contract is satisfied, but verify pin and
   ephemeral fall-back behavior is acceptable on the new platform.
