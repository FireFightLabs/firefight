# FireFight Proof of Concept (PoC) Scope

**Goal**: Build minimum viable incident management flow that demonstrates core value proposition and can be extended later.

---

## PoC Definition: The Smallest Thing That Works

**Target Timeline**: 2-3 weeks
**Team**: 1 developer
**Output**: Working incident management in Slack that you can demo to first customers

---

## What to Include (Critical Path Only)

### 1. Core Incident Creation (Week 1: Days 1-3)

**Database**:
```ruby
# incidents table
- id (uuid)
- workspace_id
- name
- severity (critical, major, minor)
- status (declared, investigating, resolved)
- declared_by_id
- slack_channel_id
- declared_at
- resolved_at
- timestamps
```

**Slack Flow**:
1. User types `/ff new` in any Slack channel
2. Modal opens with:
   - Title (optional)
   - Severity (required: critical/major/minor)
   - Summary (optional)
3. User submits → Incident created

**What Happens Next**:
- ✅ Create incident record in database
- ✅ Create dedicated Slack channel (#inc-001-title)
- ✅ Post initial message in channel
- ❌ Skip: Workflows, complex automation, integrations

### 2. Incident Channel Setup (Week 1: Days 4-5)

**Auto-actions when incident created**:
1. Create Slack channel with naming convention
2. Invite user who declared incident
3. Post pinned message with incident details:
   ```
   🚨 Incident #001: Database Slowdown
   Severity: Critical
   Declared by: @john at 2:30 PM
   Status: Investigating

   [Update Status] [Change Severity] [View Timeline]
   ```
4. Set channel topic: "INC-001 | Critical | Investigating"

**Skip for PoC**:
- ❌ Video conference creation
- ❌ Status page updates
- ❌ Complex responder invitations
- ❌ Runbook attachments

### 3. Basic Incident Updates (Week 2: Days 1-3)

**Slash Commands in Incident Channel**:

**Status Updates**:
```
/ff status investigating
/ff status identified
/ff status monitoring
/ff status resolved
```

**Severity Changes**:
```
/ff severity critical
/ff severity major
/ff severity minor
```

**What Happens**:
- ✅ Update incident record
- ✅ Post update message in channel
- ✅ Update channel topic
- ❌ Skip: Complex workflows, external notifications

### 4. Simple Event Tracking (Week 2: Days 4-5)

**Database**:
```ruby
# incident_events table
- id (uuid)
- incident_id
- event_type (created, severity_changed, status_changed, resolved)
- metadata (jsonb)
- created_at
```

**Events to Track**:
1. `incident.created` - When incident declared
2. `incident.severity_changed` - When severity updated
3. `incident.status_changed` - When status updated
4. `incident.resolved` - When marked resolved

**Timeline Command**:
```
/ff timeline
```

Shows simple text list:
```
2:30 PM - Incident created (Critical)
2:35 PM - Status → Investigating
2:45 PM - Severity → Major
3:10 PM - Status → Resolved
```

**Skip for PoC**:
- ❌ Fancy timeline UI
- ❌ Event correlation
- ❌ External event sources

### 5. Incident Resolution (Week 3: Days 1-2)

**Resolution Flow**:
```
/ff resolve
```

Opens modal:
- Resolution summary (required)
- What fixed it (optional)

**What Happens**:
- ✅ Mark incident as resolved
- ✅ Update channel topic: "RESOLVED | ..."
- ✅ Post resolution message
- ✅ Archive channel (or keep open)
- ❌ Skip: Post-mortem generation, action items

### 6. Incident List (Week 3: Days 3-4)

**Commands**:
```
/ff list - Show active incidents
/ff list all - Show all incidents (last 7 days)
```

**Output**:
```
Active Incidents:
🔴 #inc-001 - Database slowdown (Critical, 45m)
🟡 #inc-002 - API errors (Major, 2h)

/ff list all
All Recent Incidents:
✅ #inc-001 - Database slowdown (Resolved, 1h ago)
🔴 #inc-002 - API errors (Major, 2h)
```

**Skip for PoC**:
- ❌ Web dashboard
- ❌ Advanced filtering
- ❌ Analytics

---

## What to Explicitly SKIP in PoC

### Infrastructure & Architecture
- ❌ Workflow orchestration (you have this, but don't use it yet)
- ❌ Background jobs (do everything synchronously)
- ❌ Webhooks (incoming or outgoing)
- ❌ Public API

### Features
- ❌ Service catalog
- ❌ Post-mortems/retrospectives
- ❌ Runbooks
- ❌ Responder management (beyond creator)
- ❌ On-call scheduling
- ❌ Integrations (Jira, PagerDuty, etc.)
- ❌ AI features
- ❌ Custom fields
- ❌ Severity escalation
- ❌ SLAs/timers

### UI/UX
- ❌ Web dashboard
- ❌ Rich timeline UI
- ❌ Charts/graphs
- ❌ Analytics
- ❌ Search

### Advanced Slack Features
- ❌ Interactive message updates
- ❌ Complex modals
- ❌ Home tab
- ❌ App mentions
- ❌ Message shortcuts

---

## PoC Architecture (Simplified)

### Models (3 total)

```ruby
# app/models/incident.rb
class Incident < ApplicationRecord
  belongs_to :workspace
  belongs_to :declared_by, class_name: "User"
  has_many :incident_events

  enum :severity, { minor: "minor", major: "major", critical: "critical" }
  enum :status, {
    declared: "declared",
    investigating: "investigating",
    identified: "identified",
    monitoring: "monitoring",
    resolved: "resolved"
  }

  def update_severity!(new_severity, by:)
    transaction do
      old_severity = severity
      update!(severity: new_severity)
      record_event("severity_changed", from: old_severity, to: new_severity, by: by)
    end
  end

  def update_status!(new_status, by:)
    transaction do
      old_status = status
      update!(status: new_status)
      record_event("status_changed", from: old_status, to: new_status, by: by)
    end
  end

  def resolve!(summary:, by:)
    transaction do
      update!(status: "resolved", resolved_at: Time.current)
      record_event("resolved", summary: summary, by: by)
    end
  end

  private

  def record_event(event_type, **metadata)
    incident_events.create!(
      event_type: "incident.#{event_type}",
      metadata: metadata
    )
  end
end

# app/models/incident_event.rb
class IncidentEvent < ApplicationRecord
  belongs_to :incident
end

# app/models/user.rb - already exists
# app/models/workspace.rb - already exists
```

### Services (2 total)

```ruby
# app/services/incident_service.rb
class IncidentService
  def self.create_from_slack(workspace:, user:, params:)
    incident = workspace.incidents.create!(
      name: params[:name].presence || "Untitled Incident",
      severity: params[:severity],
      summary: params[:summary],
      declared_by: user,
      declared_at: Time.current,
      status: "investigating"
    )

    # Create Slack channel
    channel = SlackService.create_incident_channel(incident)
    incident.update!(slack_channel_id: channel["id"])

    # Post initial message
    SlackService.post_incident_message(incident)

    incident
  end
end

# app/services/slack_service.rb
class SlackService
  def self.create_incident_channel(incident)
    client = Slack::Web::Client.new(token: incident.workspace.access_token)

    channel_name = "inc-#{incident.id.split('-').first}-#{incident.name.parameterize}"[0..79]

    client.conversations_create(
      name: channel_name,
      is_private: false
    )
  end

  def self.post_incident_message(incident)
    client = Slack::Web::Client.new(token: incident.workspace.access_token)

    client.chat_postMessage(
      channel: incident.slack_channel_id,
      text: "🚨 Incident ##{incident.id[0..7]}: #{incident.name}",
      blocks: [
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: "*🚨 Incident ##{incident.id[0..7]}: #{incident.name}*\n\n*Severity:* #{incident.severity.upcase}\n*Status:* #{incident.status.humanize}\n*Declared by:* <@#{incident.declared_by.platform_user_id}>"
          }
        }
      ]
    )
  end
end
```

### Commands (4 total)

```ruby
# app/commands/new_incident_command.rb
class Commands::NewIncidentCommand < Commands::Base
  def call
    # Open modal
    open_modal(
      title: "Declare Incident",
      callback_id: "incident_create",
      blocks: [
        text_input("name", "Title", optional: true),
        select("severity", "Severity", options: [
          { label: "Critical", value: "critical" },
          { label: "Major", value: "major" },
          { label: "Minor", value: "minor" }
        ]),
        text_area("summary", "Summary", optional: true)
      ]
    )
  end
end

# app/commands/status_command.rb
class Commands::StatusCommand < Commands::Base
  def call
    incident = find_incident_from_channel
    new_status = params[:text]

    incident.update_status!(new_status, by: current_user.email)

    post_message(
      text: "✅ Status updated to: #{new_status.humanize}",
      channel: incident.slack_channel_id
    )
  end
end

# app/commands/severity_command.rb
class Commands::SeverityCommand < Commands::Base
  def call
    incident = find_incident_from_channel
    new_severity = params[:text]

    incident.update_severity!(new_severity, by: current_user.email)

    post_message(
      text: "✅ Severity updated to: #{new_severity.upcase}",
      channel: incident.slack_channel_id
    )
  end
end

# app/commands/timeline_command.rb
class Commands::TimelineCommand < Commands::Base
  def call
    incident = find_incident_from_channel

    timeline = incident.incident_events.order(:created_at).map do |event|
      "#{event.created_at.strftime('%I:%M %p')} - #{format_event(event)}"
    end.join("\n")

    post_ephemeral(
      text: "📊 *Incident Timeline*\n\n#{timeline}"
    )
  end

  private

  def format_event(event)
    case event.event_type
    when "incident.created"
      "Incident created (#{event.metadata['severity']})"
    when "incident.severity_changed"
      "Severity: #{event.metadata['from']} → #{event.metadata['to']}"
    when "incident.status_changed"
      "Status: #{event.metadata['from']} → #{event.metadata['to']}"
    when "incident.resolved"
      "Resolved: #{event.metadata['summary']}"
    end
  end
end
```

### Routes

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    # Slack commands
    post 'commands', to: 'commands#create'

    # Slack interactions (modals)
    post 'interactions', to: 'interactions#create'
  end
end
```

---

## Database Schema (PoC)

```ruby
# db/migrate/xxx_create_incidents.rb
create_table :incidents, id: :uuid do |t|
  t.uuid :workspace_id, null: false
  t.uuid :declared_by_id, null: false

  t.string :name
  t.text :summary
  t.string :severity, null: false, default: "minor"
  t.string :status, null: false, default: "investigating"

  t.string :slack_channel_id

  t.datetime :declared_at, null: false
  t.datetime :resolved_at

  t.timestamps

  t.index [:workspace_id, :status]
  t.index :severity
  t.index :declared_at
end

# db/migrate/xxx_create_incident_events.rb
create_table :incident_events, id: :uuid do |t|
  t.uuid :incident_id, null: false
  t.string :event_type, null: false
  t.jsonb :metadata, default: {}
  t.datetime :created_at, null: false

  t.index [:incident_id, :created_at]
  t.index :event_type
end

add_foreign_key :incidents, :workspaces
add_foreign_key :incidents, :users, column: :declared_by_id
add_foreign_key :incident_events, :incidents
```

**Total: 2 tables, ~20 columns**

---

## PoC User Flow (Demo Script)

### Scenario: Database Slowdown

**Step 1: Declare Incident**
```
User: /ff new
Modal:
  - Title: "Database slowdown"
  - Severity: Critical
  - Summary: "Users seeing 5s delays on checkout"
User: [Submit]
```

**Step 2: Channel Created**
```
Bot creates: #inc-a1b2c3d4-database-slowdown
Bot posts:
  🚨 Incident #a1b2c3d4: Database slowdown
  Severity: CRITICAL
  Status: Investigating
  Declared by: @john
```

**Step 3: Investigation**
```
[Team discusses in channel]
User: /ff status identified
Bot: ✅ Status updated to: Identified

User: /ff severity major
Bot: ✅ Severity updated to: MAJOR
```

**Step 4: View Timeline**
```
User: /ff timeline
Bot:
  📊 Incident Timeline

  2:30 PM - Incident created (critical)
  2:35 PM - Status: investigating → identified
  2:45 PM - Severity: critical → major
```

**Step 5: Resolution**
```
User: /ff resolve
Modal:
  - Summary: "Restarted stuck replica"
  - What fixed it: "Replica had lock contention"
User: [Submit]

Bot: ✅ Incident resolved!
Bot updates channel topic: RESOLVED | Database slowdown
```

---

## Success Criteria for PoC

### Must Have (Can't Demo Without)
- ✅ Declare incident from Slack
- ✅ Auto-create dedicated channel
- ✅ Update status via commands
- ✅ Update severity via commands
- ✅ View simple timeline
- ✅ Resolve incident

### Nice to Have (Can Add Later)
- ⏭️ List active incidents
- ⏭️ Search incidents
- ⏭️ Invite responders
- ⏭️ Interactive buttons

### Definitely Later
- ⏭️ Web dashboard
- ⏭️ API
- ⏭️ Webhooks
- ⏭️ Workflows
- ⏭️ Integrations
- ⏭️ AI features

---

## PoC Timeline Breakdown

### Week 1: Core Incident Creation (40 hours)

**Days 1-2 (16 hours)**:
- [ ] Database migrations (incidents + incident_events)
- [ ] Incident model with basic methods
- [ ] IncidentEvent model
- [ ] Tests

**Days 3-4 (16 hours)**:
- [ ] `/ff new` command
- [ ] Modal for incident creation
- [ ] Handle modal submission
- [ ] IncidentService.create_from_slack

**Day 5 (8 hours)**:
- [ ] SlackService.create_incident_channel
- [ ] SlackService.post_incident_message
- [ ] Test end-to-end flow

### Week 2: Updates & Timeline (40 hours)

**Days 1-2 (16 hours)**:
- [ ] `/ff status` command
- [ ] `/ff severity` command
- [ ] Update incident record + create events
- [ ] Post update messages to channel

**Days 3-4 (16 hours)**:
- [ ] `/ff timeline` command
- [ ] Format events for display
- [ ] Event tracking on all updates
- [ ] Tests

**Day 5 (8 hours)**:
- [ ] `/ff resolve` command
- [ ] Resolution modal
- [ ] Handle resolution
- [ ] Update channel topic

### Week 3: Polish & Demo Prep (40 hours)

**Days 1-2 (16 hours)**:
- [ ] `/ff list` command (active incidents)
- [ ] Error handling
- [ ] Edge cases (channel not found, permissions)
- [ ] Validation

**Days 3-4 (16 hours)**:
- [ ] UI polish (message formatting)
- [ ] Better error messages
- [ ] Help command
- [ ] Documentation

**Day 5 (8 hours)**:
- [ ] Testing with real Slack workspace
- [ ] Demo script
- [ ] Bug fixes
- [ ] Deploy to staging

---

## What You Get After 3 Weeks

### Working Product
- ✅ Declare incidents from Slack
- ✅ Dedicated incident channels
- ✅ Update severity and status
- ✅ Track all changes as events
- ✅ View incident timeline
- ✅ Resolve incidents
- ✅ List active incidents

### Foundation for Growth
- ✅ Database schema in place
- ✅ Event tracking system working
- ✅ Slack integration patterns established
- ✅ Command routing working
- ✅ Service layer for business logic

### Ready to Add Next
- ⏭️ Workflow orchestration (you already have it!)
- ⏭️ Web dashboard
- ⏭️ API
- ⏭️ Webhooks
- ⏭️ More commands
- ⏭️ Integrations
- ⏭️ AI features

---

## Extension Path (Post-PoC)

### Week 4: Connect to Workflow System
- [ ] IncidentCreationWorkflow
- [ ] Auto-invite responders
- [ ] Create video conference
- [ ] Background jobs

### Week 5-6: Web Dashboard
- [ ] Incident list page
- [ ] Incident detail page
- [ ] Timeline visualization

### Week 7-8: Public API
- [ ] API authentication
- [ ] CRUD endpoints
- [ ] Webhooks (outbound)

### Week 9-10: First Integration
- [ ] Integration framework
- [ ] Jira integration (bi-directional sync)

### Week 11+: Advanced Features
- [ ] Service catalog
- [ ] Post-mortems
- [ ] Runbooks
- [ ] AI features

---

## Decision: What to Build for PoC

### Recommendation: Go with Simplified PoC (3 weeks)

**Why**:
1. ✅ You can demo to customers in 3 weeks
2. ✅ Validates core value prop (incident management works)
3. ✅ Foundation is solid for extension
4. ✅ Doesn't waste time on features you might not need
5. ✅ Fast feedback loop

**What you're NOT building**:
- Anything you already have (workflows, auth, Slack OAuth)
- Anything you can add later without rearchitecting
- Features competitors have that users may not need

**What makes this a good PoC**:
- Real incident flow works end-to-end
- Uses Slack (primary interface)
- Event tracking proves architecture
- Can extend without throwing away code

---

## Next Steps

1. [ ] Review this PoC scope
2. [ ] Decide if 3 weeks is acceptable timeline
3. [ ] Identify any must-have features missing from PoC
4. [ ] Create first sprint (Week 1 tasks)
5. [ ] Start building!

**First Task**: Create incidents and incident_events migrations
**First Demo**: End of Week 1 - `/ff new` working with channel creation
