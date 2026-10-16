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

## Cards and alerts

Slack's card block is how a message says "this is one thing", and an alert line how it ended. Both are built with the
shared builders in `app/adapters/slack/blocks/` (see An investigation in a channel for their limits and fallback),
never by hand:

```ruby
Slack::Messages::WholeCard.build(rich: rich, title: "INC-003 · Checkout is slow", subtitle: "Minor · Investigating · Lead <@U1>",
                                 body: summary, quoted: true, actions: [ join, subscribe, open ], icon: Slack::Emoji::DECLARED)

Slack::Blocks::Alert.new(level: Slack::Blocks::Alert::LEVEL_SUCCESS, text: "Resolved by <@U1> after 1h 12m",
                         emoji: Slack::Emoji::RESOLVED).to_blocks(rich: rich)
```

- **The announcement, an incident update and a subscriber's direct message are cards.** Their body is what a person
  wrote, so they go through `WholeCard`, which never cuts it: a body that fits Slack's card goes inside, a longer one
  (and every body when the card is drawn plain) follows as sections, quoted line by line with `quoted: true`.
- **Resolved, reopened and escalated are alert lines**, `Blocks::Alert` at success or warning. Slack refuses the alert
  block in messages, so in a message it is always a section led by its emoji. `emoji:` gives it the concept's own
  (`Slack::Emoji::REOPENED`) in place of the level's, so a reopen and an escalation never look alike.
- **Every post or update of a card goes inside `with_rich_blocks`**, which posts the plain version at once when the
  workspace's Slack refuses the newer blocks.

## The divider is not decoration

Slack draws no boundary between consecutive bot messages. Without a divider
under the title, a message runs straight into the one above it and a thread
becomes a wall. **A message with a body gets a divider.** This has been shipped
wrong more than once, most visibly on cancellation, where two lifecycle events
in the same thread rendered at different weights.

The only messages that skip it are the ones with nothing to separate: a title
and a context line, no body. `Alert`, `LeadAssignment`, `PackAnswer` and a reopen with no reason are the whole list. A
rich card draws its own edges, so it needs none.

## Asking before a change

Every request Halon makes reads the same, whether it is a confirmation in a chat (`AgentConfirmation`), a call an
approval rule held (`HeldCall`) or the request an approver gets (`Approval`): a card titled ":raised_hand: Halon wants to:
add a commit to PR #856", one line on what it changes or why, and the buttons, Approve (Deny for an approver), Cancel and
Details. Nothing in the card is code: no tool names, arguments, ids or hashes, and the reads and reasons are under
Details, a modal. When Halon read text from outside that holds the change's own values, the line carries one italic
caution. Once answered the same message is redrawn to one line saying how it stands, or to a checklist while an approved
code change runs (`ChangeProgress`, its parts from `Chat::CodeFixProgress#stages`), ending on done with the page it
made, failed with why, or cancelled by whom. See docs/ai.md, Some changes wait for the person to confirm.

```
:raised_hand:  Halon wants to: add a commit to PR #856
Address the review comments on PR #856 as you asked.        [Approve] [Cancel] [Details]
                         ... after Approve ...
:arrows_counterclockwise:  plan "Add a commit to PR #856"
  ✓ Write the change   3 files changed
  ◌ Check the change
  ◌ Open a pull request
Approved by @Dana  ·  started 15:05                          [Details]
                         ... when it ends ...
:white_check_mark:  Add a commit to PR #856
Done  ·  github.com/FireFightLabs/firefight/pull/856  ·  approved by @Dana      [Details]
```

## Title: card, alert or bold section

| | Use |
|---|---|
| card | the announcement (`Announcement`), an incident update or cancellation (`StatusUpdate`), a subscriber's update, a watch (`WatchCard`) |
| alert | resolved (`Resolution`), reopened (`Reopen`), escalated (`Escalation`) |
| bold `section` | everything else, and the plain form of both |

A **milestone** is an event that ends or restarts an incident, or pulls someone in: resolved, reopened, escalated. It
is an alert, so it reads at a glance among dozens of updates, in the channel and the announcement thread alike.
Everything else is running commentary and takes the bold section.

**The announcement and the pinned quick actions say each thing once.** The announcement is one card: the title
(`IncidentDetail.title_for`, "INC-003 · Checkout is slow"), the state on one line as its subtitle
(`IncidentDetail.state_line`, "Minor · Investigating · Lead @Dana"), the summary, and Join channel, Subscribe and Open
in Firefight. Who declared it, custom fields and linked incidents follow it. The pinned message in the incident's
channel is the title, the same state line with who declared it, the summary and the buttons. Neither lists the fields
a section each.

An update is a card whose subtitle is what changed ("Severity: Minor · Status: ~Investigating~ → Identified") and whose
body is the update, with who wrote it and when the next one is due under it. In the channel its title carries the
identifier (`scope: :inline`), in the announcement thread it does not (`scope: :announcement`).

## The announcement thread has subscribers

Every update, resolution, reopen and escalation Firefight posts in an incident's announcement thread also reaches each
subscriber, as **one short card per update** (`Slack::Messages::Subscription.digest`), never a copy of the thread reply.
The card is the incident's title, what happened as its subtitle ("Resolved by @Dana after 1h 12m", "Severity: Minor ·
Updated by @Dana"), the words of the update as its body, and Open channel, Open in Firefight and Unsubscribe. Hand
`reply_and_notify_subscribers` a lambda that builds the thread reply for whether it may be drawn rich, and the digest's
headline, body and icon. The fallback text is the identifier and the headline.

Subscription confirmations are ephemeral, built by `Subscription.notice`. Each
carries an Unsubscribe button, which the shared Subscribe button cannot,
because a confirmation is seen by one person and the announcement by everyone.
The shared button only ever subscribes.

## Emoji and spacing

- **One emoji per concept, defined once in `Slack::Emoji`.** A message names the concept (`Slack::Emoji::RESOLVED`) and
  never writes a shortcode of its own for one listed there. `test/adapters/slack/emoji_test.rb` fails if two concepts
  share one.

  | Concept | Emoji | | Concept | Emoji |
  |---|---|---|---|---|
  | declared | `:rotating_light:` | | firing alert | `:red_circle:` |
  | updated | `:memo:` | | alert resolved | `:large_green_circle:` |
  | summary | `:pencil2:` | | paged | `:pager:` |
  | resolved | `:white_check_mark:` | | approval | `:lock:` |
  | accepted | `:ballot_box_with_check:` | | pack refused | `:key:` |
  | canceled | `:wastebasket:` | | lead | `:firefighter:` |
  | reopened | `:arrows_counterclockwise:` | | severity | `:fire:` |
  | escalated | `:fire_engine:` | | Halon | `:sparkles:` |
  | acknowledged | `:ok_hand:` | | warning to an admin | `:warning:` |
  | reminder | `:alarm_clock:` | | subscribe, unsubscribe | `:bell:`, `:no_bell:` |

- **Every title opens with an emoji.** It is the fastest thing to scan for.
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
- **A body that can run to several lines is quoted line by line.** mrkdwn's
  `>` covers one line, so `"> #{message}"` quotes the first line and leaves the
  rest bare. An update's message is markdown, so `Formatting.quoted_markdown`
  converts it (links, bold, `- ` items drawn as `•`) and prefixes every line,
  a blank one with a bare `>`. The prefixes add length, so
  `StatusUpdate.body_sections` carries a long update on into further sections
  at line boundaries rather than letting it pass the 3000 character limit.
  The timeline modal (`IncidentTimelineFormatter`) quotes an update's message
  the same way under its title, follows it with what the update changed
  through `Formatting.diff_text` (values escaped, times as Slack dates), and
  cuts the entry at a line boundary before the section limit.
- **An action item tracked in an issue tracker carries the issue's link**
  after its description (`Action.described`). The description came from the
  tracker, so it is escaped.
- **An item carries Rename, and Unassign while someone holds it**, and its
  done message carries Reopen and Rename (`Action.done_controls`). Rename
  opens `Modals::RenameAction`, pushed over the item list when it came from
  there, its input capped at `IncidentAction::TITLE_LIMIT`.
- **An item without an issue offers Create issue** while the workspace opens
  issues (`Action.issue_button`, `Identifiers::CREATE_ACTION_ISSUE`), and
  "Try the issue again" once one failed. Why it is missing, or that it is being
  opened, is a context line under the item (`Action.issue_status`). A change
  that reaches the item from its issue redraws its message as it stands
  (`refresh_action_message`, `Action.current`).
- **Fields are state**, joined with `·` on one line, never a section each.
  Use `Formatting.diff_text` so a change shows its before and after rather than
  just its result.
- **Footer is attribution and metadata**, always a `context` block. Who did it,
  when the next update is due, how long it took. Never a `section`, or it
  competes with the body.
- **Separator between footer parts is `  ·  `** (`Formatting::SEPARATOR`), two spaces either side, and inside a title
  or a card's subtitle ` · ` (`IncidentDetail::SEPARATOR`). **Never a pipe**, in a message, a context line or a
  channel topic (`Incident::TOPIC_SEPARATOR`).

## Rules the API enforces, painfully

- **An `actions` block with zero elements is rejected** and the whole
  `chat.postMessage` fails. Build the elements first and drop the block when
  the list comes back empty, rather than posting an empty one. `QuickActions`
  does this.
- **An empty slot in any list is rejected too** ("must provide an object"), so
  a button a builder left out as `nil` or `false` fails the whole message.
  `Slack::Client` passes every message's and modal's blocks through
  `Slack::Blocks.compact` on the way out, which drops those slots and any
  `actions` or `context` block left with no elements. Builders should still
  leave nothing out that way, but none can fail a post over it.
- `plain_text` option labels truncate at **75 characters**, a select holds at
  most **100 options**, a `header` at **150 characters**, and a section's text
  at **3000**.
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
- **A modal's context lives in `ModalState`**, never a bare id. Builders call `encode`, handlers read `interaction.metadata`.
- **Form field block and action ids come from `Slack::Modals::FieldBlocks`** (`block_id(key)`, `input_id(key)`, `action_id(key, dispatching:)`, `picked(state, key)`). Never build a `field_<key>_block` string by hand, in a builder, a submission parser or an error anchor.
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

**Every link Halon writes reaches Slack as one people can follow.**
`Formatting.markdown_to_mrkdwn` turns markdown links (an address may hold one
level of parentheses) into `<url|label>`, keeps addresses out of the bold
conversion, and keeps a label free of `|` and `>`. Text escaped before
conversion keeps its escaped links escaped, which is how outside text is kept
from faking one. The short answer's plain lines use
`Formatting.escaped_with_links`, which escapes everything except the links the
agent wrote. A streamed answer is markdown, so `append_agent_text` writes
Slack's own `<url|label>` as `[label](url)`, and `Conversation::ChunkBuffer`
with `whole_markup` (Slack's cadence) never cuts a link, bold or code across
two appends.

## Naming people

A person is never written as `<@#{id}>` by hand. Someone who joined by email,
an agent and an API key have no Slack account, and an empty `<@>` renders as
a broken mention. `Slack::Mrkdwn.mention(actor)` takes the actor, and
`Slack::Mrkdwn.person(platform_user_id, name)` takes the two values a
workflow carries in its context (`updated_by_name` beside
`updated_by_platform_user_id`, and so on). Both mention the person when there
is an id, name them in bold otherwise, and say "someone" when there is
neither.

## Copy

Everything in [CLAUDE.md](../CLAUDE.md) applies: no em dashes, no semicolons. The product is **Firefight**, never
FireFight, and the AI is **Halon**, never "Firefight AI".
Two exceptions specific to Slack:

- **Titles may use a dash as a separator**: `INC-052 — Checkout failing`.
- **A `hint` gets a period whether you write one or not.** Slack appends it
  silently, so an unterminated hint renders differently in Slack than in the
  dashboard. This is why `NormalizedDescription` terminates on save rather than
  at render.

Sentence case for titles: "Incident canceled", not "Incident Canceled". "Resolved by Dana after 1h 12m", not
"Incident Resolved".

**A refusal never shows a raw key.** `AuthorizedDispatch.denied_message` says what the person may not do in words ("You
don't have permission to change incidents in Firefight") and which access to ask for. A form that fails because its
incident is gone says so and what to do (`Interactions::ModalCleanup::RECORD_GONE`), never "Something went wrong".

**A refusal of a mention is kept.** Halon's refusal of an @mention is said to the person alone in the thread they asked
in, and kept in their direct messages (`post_refusal`), since a message only they see is gone once they reload.

**A dialog that is about to post publicly may say so first.** Opening a dialog that cancels, closes, escalates or
reopens an incident or changes its summary posts "@Dana is escalating the incident..." in the channel
(`post_modal_placeholder`), removed once the dialog is sent or closed. A status update posts none, since what it will
say is not the channel's until it is sent.

**An admin's notice is formatted** (`PlatformAdapter::Notice`, `Messages::Notice`): a warning title, a divider, what it
means, and a button to the page that fixes it.

## Messages that are edited in place

An investigation's checklist and a fix's are edited in place the same way, see An investigation in a channel. So is a
watch's card, see A watch in Slack.

`Welcome` is the onboarding checklist in `#incidents`, rebuilt from
`WorkspaceOnboarding#stage` and updated through `update_welcome_message`
as the first incident moves. It is the one message where an edit is the right
call: the reader is already in the channel doing the steps, so nobody needs
notifying, and a checklist that posted a new message per tick would bury
itself. Its steps are numbered and a finished one shows a check in place of its
number, so progress reads without a row of empty circles. Its buttons share one
`actions` row, Declare a test incident first and primary until the first
incident exists, with the `/ff new` hint as a context line under it. `FirstIncidentWalkthrough` is the coach in the first test incident's channel:
one step per message, posted by `OnboardingWalkthroughService#advance!` as the
incident earns it (declared, lead set, first message, resolved, postmortem),
with the last posted step kept on the onboarding row so nothing posts twice. The first step is the last thing
`IncidentCreationWorkflow` puts in the channel: its step waits on the pinned quick actions and on every other step that
speaks in or fills the channel (the invites, runbooks, a carried over answer, an alert investigation's start). Those
steps are `on_failure: continue`, so one that fails for good still lets the guide post. Every other caller skips while
that step is still to run (`IncidentCreationWorkflow.opening?`), so the `incident.created` progress job cannot post it
above the quick actions. `Resolution` carries the postmortem button and a
context line naming what the draft is built from, and drops both when the
incident already has a write-up.

## An investigation in a channel

A Halon run is followed from the channel and worked in the thread. Only what everyone in the channel should see is
also sent to the channel (`post_threaded_message(broadcast: true)`, Slack's "Also send to channel"): the answer and a
fix starting. Nothing else is broadcast, a stop or a fix ending included, which the checklists say as they redraw.

- **The run's first message is its checklist** (`InvestigationRun.checklist`), the thread's parent, redrawn in place
  with `chat.update` as the run moves (`update_investigation_progress`). It is Slack's `plan` block, one task per kind
  of system Halon read (`Investigation::Progress`, read from the run's own steps, so a resumed run and a redraw say
  the same thing), at most five plus "Ran other checks", then the answer as the last task. Under it a context line
  says who started it and an Open in Firefight button. `Investigation::Delivery` redraws it at most once every
  `agent_step_update_interval` seconds and never with the same content twice, and always draws the last word.
- **A plan block takes a new `block_id` on every redraw**, which Slack asks for, so `Checklist.plan` derives it from
  what the plan says.
- **The steps themselves stream in the thread** as before (`report_agent_step`). The answer stops the stream without
  adding to it (`end_agent_steps`), so the steps stay where they were read.
- **The answer is short and plain** (`InvestigationRun.answer`), from the plain fields the agent concludes with
  (`Investigation::Finding#headline`, `sureness`, `what_is_wrong_line`, `short_evidence`, `suggested_fix_line`,
  `not_checked`): a title with the kind of answer and how sure, a divider, at most five lines (what is wrong, up to
  three facts, the suggested fix), the buttons, and what could not be checked as one italic context line. Nothing in
  it is code, so `plain` drops backticks and cuts each line short.
- **The full answer is the next thread reply** (`InvestigationRun.answer_detail`), never broadcast: the summary as the
  agent wrote it, every claim with its sources, the fix step by step with what it sends, the gaps in full and "Was this
  answer right?".
- **A fix is the same kind of checklist** (`FixProgress.build`), named for its incident ("Fix for INC-003", "Undo for
  INC-003"), posted once in the thread and the channel when it is applied and redrawn in place. The redraw is the
  record: how the fix stands is the line under the checklist ("Applying the fix · 1 of 2 steps done", "Fix applied · 2
  of 2 steps done", "Fix stopped: 1 of 2 steps failed · 1 of 2 steps done"), never a second post, and Try again
  redraws the same message back to applying. Each step is its short name (`RemediationStep#shown_title`), never the
  instructions, with how it stands:
  - A step that went through shows what it produced as a link (`RemediationStep::Outcome`, kept in `outcome_label` and
    `outcome_url` when the step ends): "Opened a pull request: PR #856", where PR #856 is a `link` element in the plan
    block and `<url|PR #856>` in mrkdwn.
  - A step whose outcome already held when it ran says so (`already_done_reason`): "Already done: Uros Nikolic is
    already in #inc-003".
  - A step waiting on a person is pending, never in progress, so it never looks like work under way, and its line says
    who it waits on: who was asked to approve it ("Waiting for Ana Lee or Uros Nikolic to approve it before it runs.")
    or, once approved, who runs it ("Ana Lee approved it. Waiting for Uros Nikolic to run it.").
  - A failed or declined step says why in plain words (`failure_line`, "Couldn't open a pull request with the change:
    the code sandbox didn't start."), never the tool's own error, which stays on the run page.
  - A step only a person can do says it is theirs, naming who and where: "Your step: Invite Uros Nikolic to #inc-003.
    Then press Done." (`your_step_line`).

  Slack can show a plan block folded to its title alone, so a context line under it repeats each step, how it went
  and its link (`Checklist.blocks(summary: true)`), and the message reads in full folded. Then comes how the fix
  stands (`Slack::Blocks::Alert`), a card for each step someone can act on now (`Slack::Blocks::Card`: a failed step
  with Try again, a person's step with Done, an approved step asking "Run this step?" with how things stand now, Run
  and Dismiss), and a last card with who applied it and Undo fix, Cancel fix and Open in Firefight.

```
:hammer_and_wrench:  plan "Fix for INC-003"
  ✓ 1. Open a pull request with the change   Opened a pull request: PR #856
  ✗ 2. Roll back checkout   Couldn't roll back checkout: the tool reported an error.
✓ 1. Open a pull request with the change  Opened a pull request: PR #856   (context line, readable folded)
✗ 2. Roll back checkout  Couldn't roll back checkout: the tool reported an error.
:x:  Fix stopped: 1 of 2 steps failed  ·  1 of 2 steps done
card  :x: Couldn't roll back checkout: the tool reported an error.   Step 2   [Try again]
card  Applied by @Dana                                      [Undo fix] [Open in Firefight]
```

**Cards and alerts go through `Slack::Blocks`.** `Card.new(title:, subtitle:, body:, actions:, icon:)` and
`Alert.new(level:, text:, emoji:)` each answer `to_blocks(rich:)`, cut to Slack's limits (a card's title 150 characters, its
body 200, three buttons). Slack draws the alert block only in modals and refuses it in a message, so in a message an
alert is always a section led by its level's emoji, and `to_blocks(rich: true, modal: true)` asks for the alert block
in a modal.

**A workspace whose Slack does not show the newer blocks** (plan, card) gets the same content as plain blocks: a
title, a divider and one line per task marked by status, and each card as a section, a context line and its buttons.
Slack answers a refused block with `invalid_blocks`, which the client raises as `AdapterError::Unrenderable`.
`with_rich_blocks` then posts the plain version at once and remembers the refusal on the workspace
(`platform_data["plan_blocks_refused_at"]`, the name it had when plan blocks were the only ones), so later messages go
plain without asking, and tries the newer blocks again after a week in case the workspace changed plans.

## A watch in Slack

A watch Halon keeps is **one card per place it reports**, edited in place as it moves (`Messages::WatchCard`): one in
the chat's thread and one in the asker's direct messages, each kept on the watch (`thread_card_*`, `direct_card_*`). The
first thing the watch says in a place claims posting the card with a guarded update, so two workers never post it
twice, and everything after redraws it from how the watch stands now. A milestone never posts a message of its own:
milestones and progress stay in the chat and on the run's page.

The card is three things in plain words, and nothing in it is code (no pod ids, class names or error strings):

- The title is what the watch is for, the person's purpose or else its title, unquoted and led by the state's emoji
  (`:eyes:` watching, `:white_check_mark:` done, `:x:` failed, `:hourglass:` timed out, `:octagonal_sign:` stopped).
- The subtitle is the state in a word, Watching, Done, Failed, Timed out or Stopped (`Chat::Watch::Shown.state_word`).
- The body is one short line on why (`Shown.why`), the step it is on while it goes and the watch's `end_reason` once it
  ended.

While it goes it offers Stop, Open the run (when the provider gave the run's page) and, in direct messages, Open the
chat for a dashboard chat. Stop asks first ("Halon stops watching this and says so here. It will not report on it
again.") and never quotes the title. Once ended it offers only Open the run and Open the chat.

**Editing a message notifies nobody**, so when the watch ends (done, failed, timed out, or stopped by anyone but the
person who asked) it also posts one short line of its own beside each card, a `Blocks::Alert` led by the same emoji.
The fallback text of both is the state, what it is for and why, so a notification reads the same as the card.

```
card  :eyes:  Ship main                                        (while it goes)
      Watching
      1 of 2 steps done. Web deploy is running.          [Stop] [Open the run] [Open the chat]
                         ... when it ends, the same card ...
card  :white_check_mark:  Ship main
      Done
      Took 7 minutes. web is serving 7676c83.                  [Open the run] [Open the chat]
:white_check_mark:  *Done: Ship main.* Took 7 minutes. web is serving 7676c83.   (a new line, which notifies)
```

The card goes through `with_rich_blocks`, so a workspace whose Slack does not show cards gets the same words as a
section, a context line and the buttons. See docs/ai.md, What it says, and where.

## Asking for a pack

`PackRefusal` is posted in a chat's thread when Halon was refused a change for want of a pack. It names the pack and
the workspace admins and carries Ask an admin, which only the person refused can use, and once they ask it is redrawn
to say when. `PackRequest` is the direct message each admin gets with Give pack and a link to the Permissions screen,
redrawn to say who gave or dismissed it. `PackAnswer` tells the member how it was answered, by direct message and as a
short note in each Slack thread the change was refused in. See docs/integrations.md, Asking an admin for a pack.

## Asking about memories

`LearnedMemories` is every message that asks people to decide on memories: what an incident or its postmortem taught,
what a chat or run learned or disputed, and the weekly reminder of what nobody confirmed (`:bell:`), in an incident's
channel or by direct message. A reminder opens with one line saying how many wait and why confirming matters, then each
memory with Confirm, Not right and Correct, and a footer linking the Memory page. See docs/ai.md, Reminders reach the
person who should know.

## Proposing a handbook edit or page

`HandbookProposal` (`:ledger:`) is posted in the thread a chat or run speaks in when something Halon read contradicted
a handbook page, or when it drafts a new page. The body is the page's title and the wording Halon would write, quoted,
then what the page says now for an edit, a context line with why, Accept, Edit and Dismiss, and a footer saying nothing
changes until someone accepts. A page longer than a section holds is cut with a line saying the Handbook page shows it
whole, and one longer than a form takes has no Edit, since it is edited on the Handbook page. Edit opens
`EditHandbookProposal`, which accepts with the person's wording. Once decided it is redrawn without the buttons or the
old wording, with who decided in a context line. See docs/ai.md, Halon proposes handbook pages and edits.

## Halon in a thread

- **Halon shows it is working and when it is done.** A person's mention or direct message gets :eyes:
  (`mark_working`) and the conversation remembers it (`Conversation#acknowledged!`). When the turn answers, or asks to
  confirm, each remembered message loses :eyes: and gets :heavy_check_mark: (`mark_done`), once. A refused message just
  loses :eyes: (`unmark_working`). A mention added to a live investigation keeps :eyes: until the run's own answer.
- **A step line is plain words** (`Chat::Tools::Step#shown_line`): the words the agent wrote for the call, or the kind
  of system it read as an investigation's checklist names it ("Read the code", "Checked recent deploys"), never a tool's
  name, its connection or a file. A coding agent's progress under it is counts and how it ended
  (`CodeFixProgress#thread_line`), never the file it read or the command it ran.
- **A reply is never cut.** `AgentReply` and `AiResponse` break text into sections at line ends, then spaces
  (`Formatting.sections`), close and reopen a code block a break falls inside, and run on into further messages past
  45 blocks (`Formatting.message_parts`).
- **Links always render.** `Formatting.markdown_to_mrkdwn` turns `[label](url)` into `<url|label>`, an address with
  parentheses and a link with a title included.

## Answering in direct messages

When a person writes to Halon in the app's direct messages, the answer is a reply under their message, streamed like a
thread chat's (`Conversation::Delivery`), because Slack streams only into a thread. Everything the chat posts after
that (requests to approve a change, plans, watch cards, handbook proposals) goes in the thread the person last wrote in,
never as a new top-level DM. A reply under one of Firefight's own DMs is answered in that thread too, by the person's
chat. A refusal is one plain line in the same thread. See docs/ai.md, Direct messages.

## Posting in a channel

`ChannelPost` (`:mega:`) is a message posted as Firefight in a channel someone named, such as release notes in
#general, by `post_to_channel` from Halon's chat, a runbook step or an outside agent over MCP. Title, divider, the
message as the body, and who asked in the footer. Halon or an outside agent wrote the words, not a person in one of our
modals, so the message is escaped with `Slack::Mrkdwn.escape` before `Formatting.quoted_blocks` draws its markdown,
and a post can never ping `@here` or the channel or fake a link. A long one runs on into further sections.

```
:mega:  *Message from Halon*
─────────────────────────
> Release 2.4 is out.
>
> • Faster search
Posted by Halon at the request of @Dana
```

From an outside agent the title is "Message from Firefight" and the footer "Posted through Firefight by" its principal,
named in bold when it has no Slack account. The fallback text is the title and the message's first line.

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
