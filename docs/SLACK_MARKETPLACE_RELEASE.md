# Slack Marketplace Release Workflow

> Complete audit workflow for submitting Firefight to the Slack Marketplace.
> Source: https://docs.slack.dev/slack-marketplace/slack-marketplace-review-guide

---

## Timeline Reality Check

Do not underestimate this. The realistic path from "app works" to "live on marketplace":

| Stage | Duration | Notes |
|-------|----------|-------|
| Beta with 5+ workspaces | 28+ days | Required before submission |
| Pre-submission audit | 1-2 weeks | Internal audit of this doc |
| Preliminary review | Up to 10 business days | Scope and basic config check |
| Functional review | **Up to 10 weeks** | Full testing, back-and-forth feedback |
| Fixes and resubmission | 2-4 weeks typical | After reviewer feedback |
| **Total** | **~4-6 months** | From "app is production-ready" to live |

**Plan launches at least 6 months in advance.**

---

## Blocking Requirements

These must be true before you can submit:

- [ ] App is publicly available and production-ready (not in private beta)
- [ ] Minimum 5 active installed workspaces
- [ ] 28+ days of real usage across those workspaces
- [ ] Zero known bugs on installation, usage, or uninstallation
- [ ] All features listed in submission are shipped and functional
- [ ] App does NOT support financial transactions, cryptocurrency, or NFTs
- [ ] App is NOT a coded workflow (uses `workflow.steps:execute` or similar)

---

## Pre-Submission Audit Checklist

### 1. OAuth Scopes Audit

**Principle:** "Request the smallest number of least permissive scopes."

#### Action items

- [ ] List every scope in `config/slack_manifests/production.yml`
- [ ] For each scope, document the specific feature that needs it
- [ ] Remove any scope not backing a shipped feature
- [ ] Verify no forbidden scopes are requested

#### Forbidden scope categories

| Category | Examples | Why forbidden |
|----------|---------|---------------|
| Legacy | `read`, `post`, `client` | Deprecated |
| Admin | `admin.*` | Too broad, reserved for enterprise admin apps |
| Identity | `identity.*` | Coded workflow only |
| Coded workflow | `workflow.steps:execute`, `triggers:*` | Marketplace ineligible |
| Extensive data | `search:read` | Too broad |

#### Scopes likely needed by Firefight

Document the justification for each in the submission:

| Scope | Feature | Justification |
|-------|---------|---------------|
| `channels:manage` | Create incident channels | Core incident response |
| `channels:read` | List channels, get channel info | Channel metadata |
| `channels:history` | Transcript cache for postmortems | Read messages in incident channels |
| `chat:write` | Post incident messages, updates, announcements | Core incident response |
| `commands` | `/firefight` slash command | Incident declaration |
| `groups:read` | Private channel support | Private incident channels |
| `groups:history` | Transcript cache for private channels | Same as channels:history |
| `groups:write` | Create private channels | Private incident response |
| `im:write` | Send DMs (lead notifications, escalations) | Lead assignment flow |
| `users:read` | Resolve user handles, member lookup | User attribution |
| `users:read.email` | Member provisioning | **CAUTION** — often flagged |
| `files:read` | File archival in incidents | Incident artifacts |
| `pins:write` | Pin quick actions, postmortems | Channel UX |
| `reactions:write` | Incident status reactions | Visual feedback |

**Do not request any scope not tied to a shipped feature.** Reviewers will ask.

---

### 2. Privacy Model Audit

**Principle:** "Users can only access content in either public channels or the private channels to which they've been added."

#### Critical: Transcript Cache

Firefight has `IncidentTranscriptCache` that stores Slack message content. This is the highest-risk area for review.

- [ ] Verify transcript cache is scoped per incident (not per user)
- [ ] At **read time** (not write time), check that the viewing user was a member of the channel when messages were posted
- [ ] Ensure messages from private channels are never exposed to users who weren't in those channels
- [ ] Cache expiration on incident close (already implemented)
- [ ] Cache cleared on workspace uninstall
- [ ] Guest user consideration: transcripts should not expose messages from channels guests can't access

#### Announcements Channel

Firefight posts incident announcements to a workspace-wide channel.

- [ ] Announcement payload does NOT include sensitive content users shouldn't see
- [ ] Users in the announcements channel but not the incident channel see only public metadata
- [ ] Private incident channels are not linked in a way that bypasses membership

#### Postmortem Generation

AI postmortem generation uses incident context including transcript messages.

- [ ] Generated postmortems only contain content the target audience can see
- [ ] When a user views a postmortem, access is checked against channel membership
- [ ] Postmortem shared via announcement does not leak private channel content

#### Slack Connect

- [ ] Test behavior with external users in shared channels
- [ ] Verify external users cannot access workspace-internal incidents
- [ ] Respect the "guest" and "external" user models

---

### 3. Installation + Uninstallation Flow

**Principle:** "Thoroughly confirmed your app's installation flow, set-up process, and end-to-end functionality, including uninstalling it."

#### Installation testing

- [ ] Fresh install on a non-development workspace (as a new customer would experience)
- [ ] OAuth flow completes without errors
- [ ] Bot is added to workspace successfully
- [ ] First-time user sees onboarding guidance
- [ ] App Home shows setup instructions
- [ ] `/firefight` command works immediately
- [ ] No errors in logs during installation
- [ ] Re-installation (reinstall after uninstall) works cleanly

#### Uninstallation handling

This is critical and often overlooked.

- [ ] App handles `app_uninstalled` event
- [ ] App handles `tokens_revoked` event
- [ ] Stored Slack tokens are deleted or marked inactive
- [ ] Background jobs for the workspace are stopped (Solid Queue)
- [ ] Workspace data retention policy is documented
- [ ] User data (transcript cache, messages) deleted per privacy policy
- [ ] No orphaned data after uninstall

#### Reinstallation after scope changes

- [ ] If scopes change, users are prompted to reinstall
- [ ] Reinstall flow preserves or cleanly migrates existing data
- [ ] No data loss on scope expansion

---

### 4. App Home Quality

**Principle:** "Build an App Home displaying customized content, instructions, and updates."

App Home is heavily scrutinized. It must be publication-quality.

#### Content requirements

- [ ] Welcome message for new installs
- [ ] Setup checklist or getting-started guidance
- [ ] List of available commands with examples
- [ ] Links to documentation, support, privacy policy
- [ ] Current workspace configuration status
- [ ] Recent incidents summary (if any)
- [ ] Opt-in controls for notifications (if DMs are sent)

#### Design quality

- [ ] No broken elements, lorem ipsum, or placeholders
- [ ] Consistent branding with main app
- [ ] Works in both light and dark mode
- [ ] Mobile-friendly layout

#### Interactive elements

- [ ] All buttons work
- [ ] All menus have proper actions
- [ ] No dead UI (audit issue 3.8 — fix before submission)
- [ ] Loading states for deferred content

---

### 5. Functional Review Preparation

Reviewers test every feature end-to-end.

#### Slash commands

- [ ] All subcommands work (`new`, `declare`, `lead`, `status`, `close`, `reopen`, `actions`, `postmortem`, `links`, `escalate`, `shoutout`)
- [ ] Unknown subcommands show helpful error
- [ ] No "test" or "debug" subcommands in production manifest
- [ ] Commands respond within 3 seconds (use async processing)

#### Modals

- [ ] All modals open from correct triggers
- [ ] Validation errors display correctly
- [ ] Submit buttons work
- [ ] Cancel buttons work
- [ ] Form state persists during interaction

#### Block actions

- [ ] All buttons trigger correct handlers
- [ ] Menu selections work
- [ ] Confirmations appear where needed
- [ ] No dead buttons or placeholder actions

#### Channel operations

- [ ] Channel creation succeeds
- [ ] Channel naming follows documented pattern
- [ ] Channel topic/purpose set correctly
- [ ] Archival on incident close works
- [ ] Unarchival on incident reopen works

#### Messaging

- [ ] Incident announcement posts
- [ ] Quick actions message posts and buttons work
- [ ] Update messages post to threads
- [ ] Resolution messages post correctly
- [ ] Lead assignment DMs send

#### Edge cases reviewers will test

- [ ] App behavior when bot is removed from a channel
- [ ] App behavior when bot is not invited to a channel it needs
- [ ] App behavior with deleted users
- [ ] App behavior with workspace admin actions
- [ ] App behavior on Slack rate limits

---

### 6. Security Audit

- [ ] Slack signing secret verification on all incoming requests
- [ ] Request timestamp validation (5-minute replay window)
- [ ] HTTPS only — no HTTP endpoints
- [ ] Webhook endpoints verify signatures
- [ ] No secrets in logs or error messages
- [ ] Credentials encrypted at rest (Rails encrypted attributes)
- [ ] SQL injection prevention (parameterized queries only)
- [ ] No user input in raw SQL anywhere
- [ ] CSRF protection on web endpoints
- [ ] Rate limiting on API endpoints

---

### 7. Documentation Requirements

#### Required URLs

- [ ] Privacy policy URL (public, accessible without login)
- [ ] Terms of service URL
- [ ] Support contact email
- [ ] Documentation / help URL

#### Content requirements

- [ ] Setup guide (install → first incident)
- [ ] Feature documentation for all commands and flows
- [ ] Troubleshooting guide
- [ ] Privacy policy covers Slack data handling, transcript storage, AI processing
- [ ] Terms cover acceptable use, service availability, data retention

#### Support

- [ ] Active support email that gets responses
- [ ] Response time SLA documented
- [ ] Escalation path for reviewer questions

---

### 8. Submission Materials

#### Video demo

Required for new submissions. Must show:

- [ ] Full OAuth installation flow from start to finish
- [ ] Initial setup and configuration
- [ ] End-to-end usage of core features:
  - Declare an incident from `/firefight`
  - Update the incident
  - Assign a lead
  - Post updates
  - Close the incident
  - View postmortem
- [ ] Uninstallation flow
- [ ] Narrated with clear explanations
- [ ] High quality (1080p minimum)

#### Test credentials

- [ ] Test workspace where reviewers can install Firefight
- [ ] Test account credentials if paid features exist
- [ ] Dummy data pre-populated in test workspace
- [ ] Test credentials for any connected third-party services

#### Listing content

- [ ] App name, short description, long description
- [ ] Feature list with screenshots
- [ ] Category: "Productivity" or "Developer Tools" (not "Analytics")
- [ ] Supported languages
- [ ] Pricing tier (Free + paid plans if applicable)

---

### 9. Enterprise Grid Testing

If any of your 5 design partners is on Enterprise Grid, test:

- [ ] Org-level install vs workspace-level install
- [ ] Cross-workspace incident scenarios
- [ ] Shared channels across workspaces
- [ ] Org-wide admin permissions
- [ ] User discovery across workspaces in the grid

---

### 10. Ongoing Obligations (Post-Approval)

After approval, you are committed to:

- [ ] Subscribe to Slack changelog
- [ ] Monitor deprecation notices
- [ ] Update within Slack's deprecation timelines (usually 6-12 months)
- [ ] Respond to support requests from marketplace users
- [ ] Maintain minimum quality bar (low bug rate, good uptime)
- [ ] Re-review required for major feature changes
- [ ] Version history and changelog visible to users

---

## Firefight-Specific Risk Areas

Ranked by likelihood of review friction.

### High risk

1. **Transcript cache privacy model** — storing Slack message content is a high-scrutiny area. Must have membership checks at read time, not just at write time. Document this clearly in the privacy policy and be ready to explain it to reviewers.

2. **AI postmortem generation** — sending Slack content to an LLM (Anthropic) is a data-processing relationship that must be disclosed in the privacy policy. Reviewers will ask about data handling, retention, and third-party processing.

3. **Scope count** — Firefight needs many scopes. Expect reviewers to push back on any scope that isn't clearly justified. Have the feature-to-scope mapping ready.

### Medium risk

4. **Channel archival behavior** — automatic archival on incident close is a destructive-looking action. Document the workflow clearly and ensure it's reversible.

5. **Bot added to many channels** — Firefight creates channels and invites users. Reviewers may test what happens with private channels, archived channels, and channels where the bot lacks permissions.

6. **Ability Gateway (future)** — when the gateway is live, inbound webhooks from external services (Datadog, etc.) may need additional justification. Plan the scope impact before submitting.

### Low risk

7. **Multi-workspace support** — well-designed with `workspace_id` scoping, should be fine.

8. **Slash command coverage** — standard pattern, should pass without issue.

---

## Workflow: From "Ready" to "Live"

### Phase 1: Internal Audit (1-2 weeks)

1. Complete Priority 1 + Priority 2 fixes from `CODEBASE_AUDIT.md`
2. Walk through every checklist item in this doc
3. Fix all issues found
4. Verify `bin/ci` passes with full test suite

### Phase 2: Private Beta (4+ weeks)

5. Recruit 5-10 design partners
6. Deploy to production on Hetzner (see `PRODUCTION_DEPLOYMENT.md`)
7. Onboard partners with manual support
8. Monitor usage via Grafana dashboards
9. Fix bugs as they surface
10. Collect feedback for listing content

### Phase 3: Submission Prep (1-2 weeks)

11. Verify minimum 5 active workspaces with 28 days usage
12. Create video demo
13. Write listing content (description, features, screenshots)
14. Set up test workspace with credentials
15. Publish privacy policy, terms, support docs
16. Complete all checklist items in this doc

### Phase 4: Preliminary Review (up to 2 weeks)

17. Submit app via Slack developer portal
18. Address preliminary review feedback
19. Expect questions about scopes

### Phase 5: Functional Review (up to 10 weeks)

20. Reviewers test full installation and usage
21. Respond to feedback promptly
22. Fix any issues and resubmit
23. Repeat until approved

### Phase 6: Launch

24. App goes live on marketplace
25. Subscribe to Slack changelog
26. Monitor for incoming installs
27. Provide support per documented SLA

---

## Reference

- Slack Marketplace Review Guide: https://docs.slack.dev/slack-marketplace/slack-marketplace-review-guide
- Slack API Changelog: https://api.slack.com/changelog
- Slack Platform Developer Portal: https://api.slack.com/apps
