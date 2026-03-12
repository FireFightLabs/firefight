# Feature Review Checklist

End-to-end review of all current Firefight features, ordered as a user would experience them.

---

## Onboarding

- [x] Slack OAuth login
- [x] Dashboard redirect after login
- [x] Workspace first-install: creates `#firefight-incidents`, sets topic/description, posts welcome message, invites installer

---

## App Home

- [ ] `/ff` or `/ff home` — opens home modal
- [ ] Home modal shows active incidents and quick links
- [ ] "Share incidents channel" button works

---

## Incident Creation

- [ ] `/ff new` — opens creation modal
- [ ] "Create Incident" global shortcut opens modal
- [ ] Modal fields: name, severity, summary, visibility
- [ ] After submit: incident channel created, quick actions pinned, announcement posted, declarer invited

---

## Incident Channel — Quick Actions (pinned message)

- [ ] All buttons render: Update Summary, Send Update, Set Lead, Escalate, Invite, Actions, Follow-ups, Close, Timeline, Link Related
- [ ] Buttons update after state changes (status, severity, lead, close/reopen)

---

## Incident Status

- [ ] `/ff status` — opens status update modal
- [ ] Channel topic updates on change
- [ ] Announcement updates on change

---

## Incident Severity

- [ ] `/ff severity` — opens severity update modal
- [ ] Channel topic updates on change
- [ ] Announcement updates on change

---

## Incident Lead

- [ ] `/ff lead` — opens lead assignment modal
- [ ] "Set Lead" quick action button works
- [ ] Lead expectations message posted in channel
- [ ] Channel topic and announcement update

---

## Incident Summary

- [ ] `/ff summary` — opens summary edit modal
- [ ] "Update Summary" quick action button works
- [ ] Quick actions and announcement update

---

## Incident Updates

- [ ] `/ff update` — opens update modal
- [ ] "Send Update" quick action button works
- [ ] Update posted in incident channel
- [ ] Update posted as thread in announcements channel

---

## Incident List

- [ ] `/ff list` — shows top 10 active incidents sorted by severity (ephemeral)

---

## Timeline

- [ ] `/ff timeline` — shows last 15 events
- [ ] "Load more" button loads next page (up to 45 events total)
- [ ] Events captured: status changes, severity changes, lead assignment, messages, files, actions, follow-ups

---

## Escalation

- [ ] `/ff escalate` — opens escalation modal (user + reason)
- [ ] Escalation message posted in incident channel
- [ ] Escalation thread posted in announcements channel
- [ ] DM sent to escalated user with acknowledge button
- [ ] Acknowledge button records acknowledgment

---

## Invite Responders

- [ ] `/ff invite` — opens user selector modal
- [ ] Selected users invited to incident channel
- [ ] Notification message posted in channel

---

## Actions

- [ ] `/ff actions` — opens actions modal
- [ ] "Add Action" quick action button works
- [ ] Create action: description, assignee (optional), status
- [ ] "Pick Up Action" button claims action
- [ ] "Mark Done" button completes action
- [ ] 🔥boom emoji reaction on a message → creates action from that message

---

## Follow-ups

- [ ] `/ff followups` — opens follow-ups modal
- [ ] "Add Follow-up" quick action button works
- [ ] ➡️ emoji reaction on a message → creates follow-up from that message

---

## Shoutouts

- [ ] `/ff shoutout` — opens shoutout modal (user + message)
- [ ] Recognition message posted in incident channel
- [ ] 🔥 (heart-on-fire) emoji reaction → prompts shoutout creation

---

## Incident Linking

- [ ] `/ff link` / `/ff relate` / `/ff duplicate` — opens search + select modal
- [ ] Relationship message posted in both incident channels
- [ ] Two-way relationship stored

---

## Close / Reopen

- [ ] `/ff close` or `/ff resolve` — opens modal with optional resolution message
- [ ] Resolution message posted in incident channel
- [ ] Resolution thread posted in announcements channel
- [ ] Quick actions update to show "Reopen" button
- [ ] `/ff reopen` — opens modal with optional reason
- [ ] Reopen message posted in incident channel and announcements thread

---

## Automatic Events

- [ ] Messages in incident channel are tracked in timeline
- [ ] File shares detected and archived
- [ ] Pin events tracked (no duplicate pinning)

---

## Logout

- [ ] Logout clears session and redirects to login page
