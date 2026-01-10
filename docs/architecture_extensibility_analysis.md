# Architecture Extensibility Analysis for Firefight

## Executive Summary

After analyzing competitor architectures (incident.io, FireHydrant, Rootly) and evaluating our current workflow system, **the simple event-tracking pattern is the correct choice AND provides all the extensibility needed for future features.**

The key insight: **You already have the building blocks for a world-class incident management platform.**

---

## Current Architecture Strengths

### 1. Polymorphic Workflow System (Your Secret Weapon)

```ruby
# workflows table
t.uuid "subject_id", null: false
t.string "subject_type", null: false
# Index: ["subject_type", "subject_id", "state"]
```

This allows **ANY entity** to have workflows attached:
- `Incident` workflows (incident creation, escalation, resolution)
- `PostMortem` workflows (template generation, review process, publishing)
- `Service` workflows (deployment, health checks, registration)
- `Integration` workflows (sync with Jira, Linear, PagerDuty)
- `Runbook` workflows (execution, validation, rollback)

**This is BETTER than delegated types** because:
- No tight coupling between incidents and workflows
- New entities get workflow orchestration for free
- Each workflow tracks its own events independently

### 2. Event System (Already Production-Ready)

```ruby
# workflow_events table
t.uuid "workflow_id", null: false
t.uuid "workflow_step_id" # optional
t.string "event_type", null: false
t.jsonb "metadata", default: {}
t.datetime "created_at", null: false
```

This pattern scales to **billions of events** (proven by Basecamp's 10+ years at scale).

**Why this beats delegated types for your use case:**
- Events are append-only (perfect for audit trails)
- JSONB metadata provides schema flexibility
- Event types are self-documenting
- Easy to query and reconstruct timelines
- Works naturally with time-series databases for analytics

---

## Proposed Architecture for Extensibility

### Core Domain Models (Simple, Mutable)

```ruby
# incidents table
create_table :incidents, id: :uuid do |t|
  t.uuid :workspace_id, null: false
  t.string :name
  t.text :summary
  t.string :severity, null: false  # Current state
  t.string :status, null: false    # Current state
  t.uuid :declared_by_id
  t.uuid :commander_id

  # Platform integration
  t.string :slack_channel_id
  t.jsonb :platform_data, default: {}

  # Custom fields (extensibility!)
  t.jsonb :custom_fields, default: {}

  t.datetime :declared_at, null: false
  t.datetime :resolved_at
  t.timestamps

  t.index [:workspace_id, :status]
  t.index [:severity, :status]
  t.index :declared_at
end

# incident_events table (immutable audit trail)
create_table :incident_events, id: :uuid do |t|
  t.uuid :incident_id, null: false
  t.string :event_type, null: false
  t.uuid :actor_id
  t.jsonb :metadata, default: {}
  t.datetime :created_at, null: false

  t.index [:incident_id, :created_at]
  t.index :event_type
  t.index :created_at  # For analytics
end

# services table (service catalog)
create_table :services, id: :uuid do |t|
  t.uuid :workspace_id, null: false
  t.string :name, null: false
  t.text :description
  t.string :status, default: "active"

  # Ownership
  t.uuid :owner_id
  t.string :team

  # Integration identifiers
  t.jsonb :integrations, default: {}  # { jira_project: "INFRA", pagerduty_service: "ABC123" }

  # Metadata
  t.jsonb :custom_fields, default: {}
  t.jsonb :platform_data, default: {}

  t.timestamps

  t.index [:workspace_id, :status]
  t.index :name
end

# service_events table
create_table :service_events, id: :uuid do |t|
  t.uuid :service_id, null: false
  t.string :event_type, null: false
  t.uuid :actor_id
  t.jsonb :metadata, default: {}
  t.datetime :created_at, null: false

  t.index [:service_id, :created_at]
  t.index :event_type
end

# incident_services (many-to-many)
create_table :incident_services, id: :uuid do |t|
  t.uuid :incident_id, null: false
  t.uuid :service_id, null: false
  t.string :impact_level  # "critical", "degraded", "monitoring"
  t.datetime :created_at, null: false

  t.index [:incident_id, :service_id], unique: true
  t.index :service_id
end

# post_mortems table
create_table :post_mortems, id: :uuid do |t|
  t.uuid :incident_id, null: false
  t.uuid :workspace_id, null: false

  t.string :status, default: "draft"  # draft, in_review, published
  t.text :summary
  t.text :impact
  t.text :root_cause
  t.text :timeline
  t.text :action_items

  # Integration
  t.string :document_url  # Google Doc, Notion, etc.
  t.jsonb :platform_data, default: {}

  t.uuid :author_id
  t.datetime :published_at
  t.timestamps

  t.index :incident_id, unique: true
  t.index [:workspace_id, :status]
end

# runbooks table
create_table :runbooks, id: :uuid do |t|
  t.uuid :workspace_id, null: false
  t.string :name, null: false
  t.text :description
  t.string :status, default: "active"

  # Runbook definition (workflow-based)
  t.string :workflow_class  # "RunbookExecutionWorkflow"
  t.jsonb :workflow_config, default: {}

  # Metadata
  t.jsonb :custom_fields, default: {}
  t.timestamps

  t.index [:workspace_id, :status]
end

# integrations table (extensibility hub)
create_table :integrations, id: :uuid do |t|
  t.uuid :workspace_id, null: false
  t.string :integration_type, null: false  # "jira", "linear", "pagerduty", "datadog"
  t.string :status, default: "active"

  # Credentials (encrypted)
  t.text :encrypted_credentials

  # Configuration
  t.jsonb :config, default: {}

  # Sync state
  t.jsonb :sync_state, default: {}
  t.datetime :last_synced_at

  t.timestamps

  t.index [:workspace_id, :integration_type]
  t.index :status
end

# webhooks table (outbound notifications)
create_table :webhooks, id: :uuid do |t|
  t.uuid :workspace_id, null: false
  t.string :name, null: false
  t.string :url, null: false
  t.string :status, default: "active"

  # Event filtering
  t.string :event_types, array: true, default: []  # ["incident.created", "incident.severity_changed"]
  t.jsonb :filters, default: {}  # { severity: ["critical", "major"] }

  # Security
  t.string :signing_secret

  # Reliability
  t.integer :retry_count, default: 3
  t.jsonb :retry_config, default: {}

  # Stats
  t.integer :success_count, default: 0
  t.integer :failure_count, default: 0
  t.datetime :last_triggered_at
  t.datetime :disabled_at

  t.timestamps

  t.index [:workspace_id, :status]
  t.index :event_types, using: :gin
end

# webhook_deliveries table (delivery tracking)
create_table :webhook_deliveries, id: :uuid do |t|
  t.uuid :webhook_id, null: false
  t.string :event_type, null: false
  t.uuid :event_id  # References incident_events, workflow_events, etc.

  t.jsonb :payload
  t.integer :attempt, default: 1
  t.integer :response_status
  t.text :response_body
  t.text :error_message

  t.datetime :delivered_at
  t.datetime :created_at, null: false

  t.index [:webhook_id, :created_at]
  t.index :event_type
  t.index [:webhook_id, :attempt]
end
```

---

## How This Architecture Supports Future Features

### 1. Webhooks ✅

**Implementation:**
```ruby
# app/services/webhook_dispatcher.rb
class WebhookDispatcher
  def self.dispatch(event_type:, event:, workspace:)
    webhooks = workspace.webhooks
      .active
      .where("? = ANY(event_types)", event_type)

    webhooks.each do |webhook|
      next unless webhook.matches_filters?(event)

      WebhookDeliveryJob.perform_later(
        webhook_id: webhook.id,
        event_type: event_type,
        event_id: event.id
      )
    end
  end
end

# Usage in Incident model
class Incident
  after_commit :dispatch_webhooks, on: [:create, :update]

  def update_severity!(new_severity, by:, reason: nil)
    transaction do
      old_severity = severity
      update!(severity: new_severity)

      event = record_event("incident.severity_changed",
        from: old_severity,
        to: new_severity,
        by: by,
        reason: reason
      )

      WebhookDispatcher.dispatch(
        event_type: "incident.severity_changed",
        event: event,
        workspace: workspace
      )
    end
  end
end
```

**Webhook payload:**
```json
{
  "event_type": "incident.severity_changed",
  "occurred_at": "2025-01-10T12:00:00Z",
  "workspace_id": "uuid",
  "incident": {
    "id": "uuid",
    "name": "Database slowdown",
    "severity": "major",
    "status": "investigating",
    "url": "https://app.firefight.dev/incidents/uuid"
  },
  "changes": {
    "severity": { "from": "critical", "to": "major" },
    "changed_by": "user@example.com",
    "reason": "Impact contained to single region"
  }
}
```

### 2. Public API for Integrations ✅

**RESTful API design:**
```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :incidents do
      member do
        post :update_severity
        post :assign_commander
        post :add_responder
        post :resolve
      end
      resources :events, only: [:index]
      resources :timeline, only: [:index]
    end

    resources :services
    resources :post_mortems
    resources :runbooks do
      member do
        post :execute
      end
    end

    resources :webhooks
  end
end

# app/controllers/api/v1/incidents_controller.rb
class Api::V1::IncidentsController < Api::BaseController
  before_action :authenticate_api_token!

  def index
    incidents = current_workspace.incidents
      .includes(:declared_by, :commander)
      .where(filters)
      .order(declared_at: :desc)
      .page(params[:page])

    render json: incidents, each_serializer: IncidentSerializer
  end

  def update_severity
    @incident.update_severity!(
      params[:severity],
      by: current_user.email,
      reason: params[:reason]
    )

    render json: @incident, serializer: IncidentSerializer
  end
end
```

**API Response:**
```json
{
  "id": "uuid",
  "name": "Database slowdown",
  "summary": "Users experiencing 5s delays on checkout",
  "severity": "major",
  "status": "investigating",
  "declared_at": "2025-01-10T12:00:00Z",
  "declared_by": {
    "id": "uuid",
    "name": "John Doe",
    "email": "john@example.com"
  },
  "commander": {
    "id": "uuid",
    "name": "Jane Smith",
    "email": "jane@example.com"
  },
  "services": [
    {
      "id": "uuid",
      "name": "Payment Service",
      "impact_level": "critical"
    }
  ],
  "slack_channel": "https://slack.com/archives/C12345",
  "timeline_url": "https://api.firefight.dev/v1/incidents/uuid/timeline"
}
```

### 3. Integrations (Jira, Linear, PagerDuty, etc.) ✅

**Integration architecture using workflows:**
```ruby
# app/workflows/integrations/jira_sync_workflow.rb
class Integrations::JiraSyncWorkflow < Workflows::Base
  def define
    step :find_or_create_jira_issue
    step :sync_incident_to_jira
    step :create_jira_comment
    step :update_incident_with_jira_link
  end

  private

  def find_or_create_jira_issue(workflow:, step:, input:)
    incident = workflow.subject
    integration = incident.workspace.integrations.jira.active.first!

    jira_client = JiraClient.new(integration.credentials)

    # Check if already synced
    if incident.platform_data["jira_issue_key"]
      return { issue_key: incident.platform_data["jira_issue_key"] }
    end

    # Create new issue
    issue = jira_client.create_issue(
      project: integration.config["project_key"],
      summary: incident.name,
      description: incident.summary,
      priority: severity_to_jira_priority(incident.severity),
      labels: ["firefight", "incident"]
    )

    { issue_key: issue.key, issue_url: issue.self }
  end

  def sync_incident_to_jira(workflow:, step:, input:)
    incident = workflow.subject
    integration = incident.workspace.integrations.jira.active.first!

    jira_client = JiraClient.new(integration.credentials)

    jira_client.update_issue(
      issue_key: input[:issue_key],
      status: status_to_jira_status(incident.status),
      priority: severity_to_jira_priority(incident.severity)
    )

    {}
  end
end

# Trigger on incident events
class Incident
  after_commit :sync_to_integrations, on: [:create, :update]

  private

  def sync_to_integrations
    workspace.integrations.active.each do |integration|
      workflow_class = "Integrations::#{integration.integration_type.camelize}SyncWorkflow"
      next unless Workflows::Base.registry.key?(workflow_class)

      Workflows::Base.registry[workflow_class].start!(self)
    end
  end
end
```

**Bi-directional sync:**
```ruby
# app/jobs/integration_sync_job.rb
class IntegrationSyncJob < ApplicationJob
  def perform(integration_id)
    integration = Integration.find(integration_id)

    case integration.integration_type
    when "jira"
      JiraSyncService.new(integration).sync_from_jira
    when "linear"
      LinearSyncService.new(integration).sync_from_linear
    end
  end
end

# app/services/jira_sync_service.rb
class JiraSyncService
  def sync_from_jira
    # Poll Jira for updates
    since = @integration.last_synced_at || 1.hour.ago

    jira_client.search_issues("project = #{project_key} AND updated > #{since}").each do |jira_issue|
      # Find matching incident
      incident = Incident.find_by(
        workspace: @integration.workspace,
        "platform_data->>'jira_issue_key' = ?", jira_issue.key
      )

      next unless incident

      # Sync status changes
      if jira_issue.status != incident.status
        incident.update_status!(
          jira_status_to_incident_status(jira_issue.status),
          by: "jira_sync",
          reason: "Synced from Jira"
        )
      end
    end

    @integration.update!(last_synced_at: Time.current)
  end
end
```

### 4. AI Components ✅

**AI-powered incident search:**
```ruby
# app/services/ai/incident_search_service.rb
class AI::IncidentSearchService
  def search(query:, workspace:, limit: 10)
    # Generate embedding for query
    embedding = OpenAI::EmbeddingService.generate(query)

    # Vector search (using pgvector extension)
    incidents = workspace.incidents
      .select("*, embeddings <=> '#{embedding}' AS distance")
      .where("embeddings <=> '#{embedding}' < 0.3")
      .order("distance")
      .limit(limit)

    # Re-rank using LLM
    OpenAI::RerankService.rerank(
      query: query,
      documents: incidents.map(&:to_search_document)
    )
  end
end

# Usage in Slack command
# /firefight similar "database connection timeout"
class Commands::SimilarIncidents < Commands::Base
  def call
    results = AI::IncidentSearchService.new.search(
      query: params[:text],
      workspace: workspace,
      limit: 5
    )

    blocks = results.map do |incident|
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: "*#{incident.name}* (#{incident.severity})\n#{incident.summary}\n<#{incident.url}|View incident>"
        }
      }
    end

    post_ephemeral(blocks: blocks)
  end
end
```

**AI data fixing (anomaly detection):**
```ruby
# app/services/ai/data_quality_service.rb
class AI::DataQualityService
  def analyze_incident(incident)
    issues = []

    # Check for missing critical fields
    issues << "Missing summary" if incident.summary.blank?
    issues << "Missing commander" if incident.commander_id.blank? && incident.severity == "critical"

    # AI-powered checks
    if incident.summary.present?
      # Check if summary matches severity
      analysis = OpenAI::CompletionService.analyze(
        prompt: "Analyze this incident summary and suggest the appropriate severity: #{incident.summary}",
        model: "gpt-4"
      )

      if analysis.suggested_severity != incident.severity
        issues << "Severity mismatch: AI suggests '#{analysis.suggested_severity}' based on summary"
      end
    end

    # Check for stale incidents
    if incident.status == "investigating" && incident.declared_at < 24.hours.ago
      issues << "Incident has been investigating for >24 hours without resolution"
    end

    issues
  end

  def suggest_fixes(incident)
    # AI-powered suggestions
    OpenAI::CompletionService.complete(
      prompt: <<~PROMPT
        Given this incident:
        Name: #{incident.name}
        Summary: #{incident.summary}
        Severity: #{incident.severity}
        Status: #{incident.status}

        Suggest improvements to the incident data and next steps.
      PROMPT
    )
  end
end
```

**AI SRE agent (future):**
```ruby
# app/services/ai/sre_agent_service.rb
class AI::SREAgentService
  def handle_incident(incident)
    # Analyze incident using AI
    analysis = analyze_incident_context(incident)

    # Suggest runbooks
    runbooks = suggest_runbooks(incident, analysis)

    # Auto-execute approved runbooks
    runbooks.filter(&:auto_executable?).each do |runbook|
      Workflows::Base.registry[runbook.workflow_class].start!(incident)
    end

    # Provide recommendations
    recommendations = generate_recommendations(incident, analysis)

    # Post to Slack channel
    slack_client.post_message(
      channel: incident.slack_channel_id,
      blocks: format_ai_recommendations(recommendations)
    )
  end
end
```

### 5. Custom Workflows and Runbooks ✅

**Your workflow system already supports this!**

```ruby
# app/workflows/runbook_execution_workflow.rb
class RunbookExecutionWorkflow < Workflows::Base
  def define
    # Steps are defined dynamically from runbook config
    runbook = subject

    runbook.workflow_config["steps"].each_with_index do |step_config, index|
      step step_config["name"].to_sym, **step_config.slice("input", "depends_on")
    end
  end

  # Dynamic step execution
  def method_missing(method_name, **args)
    step_config = subject.workflow_config["steps"].find { |s| s["name"] == method_name.to_s }
    return super unless step_config

    case step_config["type"]
    when "slack_message"
      send_slack_message(args)
    when "api_call"
      make_api_call(step_config["api_config"], args)
    when "script"
      execute_script(step_config["script"], args)
    when "wait"
      sleep(step_config["duration"])
    end
  end
end

# Usage: Creating a custom runbook
runbook = Runbook.create!(
  workspace: workspace,
  name: "Database failover",
  workflow_class: "RunbookExecutionWorkflow",
  workflow_config: {
    steps: [
      {
        name: "notify_team",
        type: "slack_message",
        input: {
          channel: "#oncall",
          message: "Starting database failover"
        }
      },
      {
        name: "check_replica_lag",
        type: "api_call",
        api_config: {
          url: "https://api.db.com/replica/lag",
          method: "GET"
        }
      },
      {
        name: "promote_replica",
        type: "script",
        script: "aws rds promote-read-replica --db-instance-identifier replica-1"
      },
      {
        name: "update_dns",
        type: "api_call",
        api_config: {
          url: "https://api.cloudflare.com/dns/update",
          method: "POST",
          body: { record: "db.example.com", value: "new-primary-ip" }
        }
      },
      {
        name: "verify_failover",
        type: "wait",
        duration: 30
      }
    ]
  }
)

# Execute runbook
workflow = RunbookExecutionWorkflow.start!(runbook)
```

### 6. Service Catalog ✅

**Already designed in the architecture above!**

```ruby
# app/models/service.rb
class Service < ApplicationRecord
  include Service::Eventable

  belongs_to :workspace
  belongs_to :owner, class_name: "User", optional: true

  has_many :incident_services, dependent: :destroy
  has_many :incidents, through: :incident_services
  has_many :service_events, dependent: :destroy

  # Dependencies
  has_many :service_dependencies, foreign_key: :service_id, dependent: :destroy
  has_many :dependencies, through: :service_dependencies, source: :depends_on

  def affected_by_incident?(incident)
    incidents.include?(incident)
  end

  def current_incidents
    incidents.where(status: ["declared", "investigating", "identified", "monitoring"])
  end

  def health_status
    return "critical" if current_incidents.where(severity: "critical").any?
    return "degraded" if current_incidents.any?
    "healthy"
  end
end

# API endpoint
GET /api/v1/services
{
  "services": [
    {
      "id": "uuid",
      "name": "Payment Service",
      "description": "Handles payment processing",
      "status": "active",
      "health": "degraded",
      "owner": {
        "id": "uuid",
        "name": "Platform Team"
      },
      "integrations": {
        "jira_project": "PAY",
        "pagerduty_service": "ABC123",
        "github_repo": "org/payment-service"
      },
      "current_incidents": [
        {
          "id": "uuid",
          "severity": "major",
          "impact_level": "degraded"
        }
      ],
      "dependencies": [
        {
          "id": "uuid",
          "name": "Database Service"
        }
      ]
    }
  ]
}
```

---

## Event-Driven Architecture Benefits

### 1. Complete Audit Trail
Every action creates an event:
- `incident.created`
- `incident.severity_changed`
- `incident.commander_assigned`
- `incident.service_affected`
- `incident.resolved`
- `workflow.started`
- `workflow.step.succeeded`
- `integration.synced`
- `webhook.delivered`

### 2. Timeline Reconstruction
```ruby
class Incident
  def complete_timeline
    # Combine incident events, workflow events, integration events
    events = []

    events += incident_events.map do |e|
      { timestamp: e.created_at, type: e.event_type, source: "incident", data: e.metadata }
    end

    events += workflows.flat_map(&:workflow_events).map do |e|
      { timestamp: e.created_at, type: e.event_type, source: "workflow", data: e.metadata }
    end

    events += webhook_deliveries.map do |d|
      { timestamp: d.created_at, type: "webhook.delivered", source: "webhook", data: { url: d.webhook.url } }
    end

    events.sort_by { |e| e[:timestamp] }
  end
end
```

### 3. Analytics and Reporting
```ruby
# MTTR (Mean Time To Resolution)
Incident.resolved
  .where("resolved_at IS NOT NULL")
  .average("EXTRACT(EPOCH FROM (resolved_at - declared_at))")

# Incidents by severity over time
IncidentEvent.where(event_type: "incident.created")
  .group_by_day(:created_at)
  .group("metadata->>'severity'")
  .count

# Most affected services
IncidentService.joins(:service)
  .where("incident_services.created_at > ?", 30.days.ago)
  .group("services.name")
  .count
  .sort_by { |_, count| -count }
```

### 4. Real-time Updates (WebSockets)
```ruby
# app/channels/incident_channel.rb
class IncidentChannel < ApplicationCable::Channel
  def subscribed
    incident = Incident.find(params[:incident_id])
    stream_for incident
  end
end

# Broadcast on events
class Incident
  after_commit :broadcast_update, on: [:update]

  private

  def broadcast_update
    IncidentChannel.broadcast_to(self, {
      action: "update",
      incident: IncidentSerializer.new(self).as_json
    })
  end
end
```

---

## Migration Path from Current State

### Phase 1: Core Incidents (Week 1-2)
1. Create `incidents`, `incident_events` tables
2. Implement Incident model with event tracking
3. Connect to existing workflow system
4. Build Slack incident creation flow

### Phase 2: Webhooks & API (Week 3-4)
1. Create `webhooks`, `webhook_deliveries` tables
2. Build webhook dispatcher and delivery system
3. Implement public API endpoints
4. API documentation (OpenAPI spec)

### Phase 3: Service Catalog (Week 5-6)
1. Create `services`, `service_events`, `incident_services` tables
2. Build service management UI
3. Connect services to incidents
4. Service health dashboard

### Phase 4: Integrations (Week 7-10)
1. Create `integrations` table
2. Build Jira integration (bi-directional sync)
3. Build Linear integration
4. Build PagerDuty integration
5. Build Datadog integration

### Phase 5: AI Components (Week 11-14)
1. Add pgvector for embeddings
2. Build incident search
3. Build data quality analyzer
4. Build AI-powered suggestions

### Phase 6: Runbooks & Postmortems (Week 15-18)
1. Create `runbooks`, `post_mortems` tables
2. Build runbook execution system
3. Build postmortem generator
4. Build postmortem review workflow

---

## Why This Beats Delegated Types

| Requirement | Delegated Types | Event-Driven Architecture |
|-------------|----------------|---------------------------|
| **Change tracking** | New recordable on each change | Event created on each change |
| **Current state** | Pointer to latest recordable | Mutable incident record |
| **Timeline** | Query events + recordables | Query events directly |
| **Extensibility** | Add new recordable types | Add new event types |
| **Complexity** | 3 tables (recordings + recordables + events) | 2 tables (incidents + events) |
| **Query performance** | Join recordings → recordables → events | Direct query on events |
| **Schema changes** | None (new recordable table) | None (new event types) |
| **Developer experience** | Abstract, harder to reason about | Simple, familiar pattern |
| **Integrations** | Recordables don't map well | Events are perfect for webhooks |
| **Analytics** | Complex queries across tables | Simple time-series queries |
| **AI/ML** | Hard to extract features | Events are natural features |

---

## Competitor Parity Analysis

### incident.io
**Their strengths:**
- Slack-native UI
- Custom fields
- Workflow automation
- Status pages

**Your advantages:**
- ✅ Polymorphic workflows (more flexible)
- ✅ Event-driven architecture (better analytics)
- ✅ Open source potential
- 🔄 Need: Custom fields (use `custom_fields` jsonb)
- 🔄 Need: Status pages

### FireHydrant
**Their strengths:**
- 350+ API endpoints
- Runbook automation
- Service catalog
- Retrospectives

**Your advantages:**
- ✅ Workflow system (matches runbooks)
- ✅ Event tracking (better than FireHydrant's)
- 🔄 Need: Service catalog (design ready)
- 🔄 Need: Retrospectives (= postmortems)

### Rootly
**Their strengths:**
- AI-powered insights
- Automatic severity detection
- Post-incident analysis

**Your advantages:**
- ✅ Workflow orchestration
- ✅ Event system for ML features
- 🔄 Need: AI integration (architecture ready)
- 🔄 Need: Severity detection (can use AI::DataQualityService)

---

## Conclusion

**The simple event-tracking pattern is the correct choice for Firefight.**

Your existing workflow system + incident events pattern gives you:
1. ✅ Complete audit trail
2. ✅ Extensibility through events and workflows
3. ✅ Integration-ready architecture
4. ✅ AI/ML-ready data structure
5. ✅ Webhook support
6. ✅ Public API foundation
7. ✅ Service catalog capability
8. ✅ Runbook execution
9. ✅ Analytics and reporting
10. ✅ Real-time updates

**You don't need delegated types.** You need what you already have: a solid foundation with polymorphic workflows and event tracking.

Focus on building features, not refactoring to complex patterns that won't provide additional value.
