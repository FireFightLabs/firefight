# Slack message design

Everything Firefight posts to Slack is built in `app/adapters/slack/messages/`
and rendered by a client that has no idea what an incident is. The blocks are
the entire user interface, so they get the same treatment as a screen: one
layout, applied everywhere, so a channel reads as one product rather than
seventeen people's ideas.

A responder reads these messages stacked on top of each other, in a thread,
under time pressure. Consistency is not tidiness here. It is the only thing
that lets someone skim a thread and find the one post that matters.

## Anatomy

Every message is the same four parts, in this order. Parts can be omitted, but
never reordered and never merged into each other.

```
title      :emoji:  *What happened*        section (mrkdwn) or header block
divider    ─────────────────────────       omitted only when there is no body
body       > what a human typed            the payload
fields     Severity: Major · Status: …     the machine-readable state
footer     Updated by @user · Next …       context block, small grey text
```

```ruby
[
  { type: "section", text: { type: "mrkdwn", text: ":memo:  *Incident updated*" } },
  { type: "divider" },
  { type: "section", text: { type: "mrkdwn", text: "> #{message}" } },
  { type: "section", text: { type: "mrkdwn", text: field_lines.join("  ·  ") } },
  { type: "context", elements: [ { type: "mrkdwn", text: "Updated by <@#{user_id}>" } ] }
]
```

## The divider is not decoration

Slack draws no boundary between consecutive bot messages. Without a divider
under the title, a message runs straight into the one above it and a thread
becomes a wall. **A message with a body gets a divider.** This has been shipped
wrong more than once, most visibly on cancellation, where two lifecycle events
in the same thread rendered at different weights.

The only messages that skip it are the ones with nothing to separate: a title
and a context line, no body. `Alert` and `LeadAssignment` are the whole list.

## Title: header block or bold section

| | Use | Where |
|---|---|---|
| `header` block | milestones | the announcement thread |
| bold `section` | everything else | incident channels, DMs, ephemerals |

A **milestone** is an event that starts, ends, or restarts an incident:
declared, resolved, canceled, reopened, escalated. There are a handful per
incident and they should be findable by scrolling. Everything else, including
ordinary status updates, is running commentary and takes the smaller title.

The distinction only applies in the **announcement thread**, where milestones
sit among dozens of updates. In the incident channel every message already
carries the identifier, so they all use the bold section.

Because one builder often serves both surfaces, this usually means a `scope:`
argument rather than two methods (see `StatusUpdate.build`).

## Emoji and spacing

- **Every title opens with an emoji.** It is the fastest thing to scan for, and
  two events that mean different things never share one. Cancellation is
  `:wastebasket:`, an update is `:memo:`.
- **Two spaces after the title emoji**, one space everywhere else. The wider
  gap is what makes a title read as a title next to a field line that starts
  the same way.
  ```
  :memo:  *Incident updated*      title
  :fire: *Severity:* Major        field line
  ```
- Header blocks are `plain_text` and need `emoji: true` for the shortcode to
  render. Sections and context are `mrkdwn` and render it either way.

## Body, fields, footer

- **Body is what a human wrote.** Quote it with `>` so it is visibly theirs and
  not the bot's. Never merge it into the title with a `\n`.
- **Fields are state**, joined with `  ·  ` on one line when there are three or
  fewer, one per line when the message is a milestone worth reading slowly.
  Use `Formatting.diff_text` so a change shows its before and after rather than
  just its result.
- **Footer is attribution and metadata**, always a `context` block. Who did it,
  when the next update is due, how long it took. Never a `section`, or it
  competes with the body.
- **Separator between footer parts is `  ·  `**, two spaces either side.

## Rules the API enforces, painfully

- **An `actions` block with zero elements is rejected** and the whole
  `chat.postMessage` fails. Build the elements first and drop the block when
  the list comes back empty, rather than posting an empty one. `QuickActions`
  does this.
- `plain_text` option labels truncate at **75 characters**, a select holds at
  most **100 options**, a `header` at **150 characters**, and a section's text
  at **3000**. Use `Formatting.truncate_block_text` rather than trusting input
  to be short.
- A `context` block holds at most **10 elements**.
- A message holds at most **50 blocks** and a modal **100**. Anything rendering
  one block per record needs a ceiling and a line saying what it held back.
  `Messages::Runbook::MAX_STEP_ROWS` and `Modals::RunbookDetail::MAX_STEPS` are
  those ceilings, sized against the header and footer around them.
- A `section` accessory is **one element**, so a row cannot carry both a button
  and a picker. Put the second control in an `actions` block, as the action
  item message does, or move it to a modal, as a runbook row does.
- A `users_select` carries **no `value`**, unlike a button. The id it acts on
  goes in the enclosing `block_id` (`ACTION_BLOCK_PREFIX`,
  `RUNBOOK_STEP_BLOCK_PREFIX`), because `action_id` has to stay an exact match
  for `InteractionDispatcher` to route it.
- **Editing a message notifies nobody.** `chat.update` is right for state a
  reader will come back to, and wrong for telling someone something happened.
  A handover and a completion both post. `IncidentActionService` owns both, so
  every surface that changes an item announces it the same way.
- **An item holds exactly one message**, the one carrying its controls. A
  handover either becomes that message, for an item that has none, or points at
  it. Posting a second set of controls looks harmless and is not: only the one
  in `message_ts` is ever updated, so the other keeps a live button on finished
  work.
- **A control inside a modal does not redraw it.** Slack leaves the open view
  exactly as it was, so a row keeps its old button and the click reads as
  broken. `Interactions::OpenModalRefresh` rebuilds the view from the same
  inputs it was opened with, keyed on its `callback_id`.
- **A modal's context lives in `Slack::PrivateMetadata`**, never a bare id.
  Invite read it as a bare incident id while the modal encoded JSON, so every
  invite failed, and its test asserted the handler's shape rather than the
  modal's, which is how that shipped.

## The fallback text is user-facing

`chat.postMessage` takes both `blocks:` and `text:`. The blocks are the message;
the `text:` is what appears in a push notification, in the channel list, and in
any client that cannot render blocks. It is read more often than the blocks on
mobile, and it must say the same thing.

A cancellation that posts through the update path once notified everyone that
the incident was "updated". Derive the fallback from the same state the blocks
derive from, never from the method name.

## Escaping

Anything that did not come from Firefight goes through `Slack::Mrkdwn.escape`:
alert titles from provider payloads, runbook names, custom field values. Slack
mrkdwn will happily interpret `<!channel>` inside an alert title and page an
entire workspace.

Text a responder typed into one of our own modals is trusted, because they
could have typed it into the channel anyway.

## Copy

Everything in [CLAUDE.md](../CLAUDE.md) applies: no em dashes, no semicolons.
Two exceptions specific to Slack:

- **Titles may use a dash as a separator**: `INC-052 — Checkout failing`.
- **A `hint` gets a period whether you write one or not.** Slack appends it
  silently, so an unterminated hint renders differently in Slack than in the
  dashboard. This is why `NormalizedDescription` terminates on save rather than
  at render.

Sentence case for titles: "Incident canceled", not "Incident Canceled".

## Adding a message

1. New module in `app/adapters/slack/messages/`, one per concept, class methods
   returning an array of blocks. No I/O, no model writes.
2. Follow the anatomy above. If you are about to skip the divider, check
   whether the message has a body.
3. Post it from `Slack::WorkspaceAdapter`, never from a handler or a job, and
   give it a `text:` that matches what the blocks say.
4. Look at it in Slack. Block Kit Builder renders a preview, but it does not
   show you what the message looks like stacked under the three before it,
   which is the thing that usually goes wrong.
