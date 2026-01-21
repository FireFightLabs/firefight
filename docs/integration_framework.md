# FireFight Integration Framework
## Supporting 67+ Integrations with AI-Powered Natural Language Interface

**Analysis Date**: January 10, 2026
**Competitor Benchmark**: incident.io (67 integrations across 6 categories)

---

## Executive Summary

**YES - Your architecture can support ALL 67 incident.io integrations AND make adding new ones trivial.**

More importantly, your workflow system + AI layer will enable:
```
❌ Old way: /ff create-ticket --project INFRA --title "Database issue"
✅ New way: /ff create a jira ticket for this incident in the INFRA project
✅ AI way:  /ff notify the team and create tracking tickets
```

The key insight: **Integrations are just workflow steps that AI can orchestrate.**

---

## Integration Categories Analysis

### 1. Issue Tracking (8 integrations)
**Platforms**: Asana, ClickUp, GitHub, GitLab, Jira, Linear, Shortcut, Zendesk

**Capabilities Required**:
- ✅ Export incident actions as tickets
- ✅ Bi-directional sync (incident updates ↔ ticket updates)
- ✅ Link PRs/commits to incidents
- ✅ Automatic status synchronization

**Architecture Support**: **PERFECT FIT**

Your workflow system already handles this:
```ruby
# app/workflows/integrations/issue_tracker_workflow.rb
class Integrations::IssueTrackerWorkflow < Workflows::Base
  def define
    step :validate_integration
    step :create_or_update_ticket
    step :sync_status
    step :add_incident_link
    step :record_sync_event
  end
end
```

### 2. Service Catalog (4 integrations)
**Platforms**: Backstage, Cortex, OpsLevel, ServiceNow CMDB

**Capabilities Required**:
- ✅ Import service definitions
- ✅ Sync service metadata
- ✅ Map services to incidents
- ✅ Update service health status

**Architecture Support**: **PERFECT FIT**

You already designed the `services` table. Just add import workflows:
```ruby
# app/workflows/integrations/service_catalog_import_workflow.rb
class Integrations::ServiceCatalogImportWorkflow < Workflows::Base
  def define
    step :fetch_catalog_data
    step :parse_services
    step :create_or_update_services
    step :sync_dependencies
    step :update_sync_state
  end
end
```

### 3. Alerts & Paging (29 integrations)
**Platforms**: Datadog, PagerDuty, Grafana, New Relic, Sentry, Prometheus, Splunk, etc.

**Capabilities Required**:
- ✅ Receive incoming webhooks/alerts
- ✅ Create incidents from alerts
- ✅ Trigger pages/escalations
- ✅ Acknowledge/resolve alerts
- ✅ Send incident updates back

**Architecture Support**: **PERFECT FIT**

This is exactly what your workflow system was built for:
```ruby
# Incoming webhook handler
# POST /api/v1/webhooks/datadog
class Api::V1::Webhooks::DatadogController < Api::BaseController
  def create
    alert = parse_datadog_alert(params)

    # Create or update incident
    incident = Incident.find_or_create_from_alert!(
      workspace: workspace,
      alert_source: "datadog",
      alert_data: alert
    )

    # Start incident workflow
    IncidentCreationWorkflow.start!(incident)

    render json: { incident_id: incident.id }
  end
end

# Outbound: Update alert when incident resolves
class Incident
  after_commit :sync_to_alert_sources, on: :update

  def sync_to_alert_sources
    return unless saved_change_to_status?

    alert_integrations.each do |integration|
      Integrations::AlertUpdateWorkflow.start!(
        self,
        integration: integration,
        action: resolve_action_for_status
      )
    end
  end
end
```

### 4. Video & Documents (6 integrations)
**Platforms**: Confluence, Google Docs, Google Meet, Microsoft Teams, Notion, Zoom

**Capabilities Required**:
- ✅ Auto-create meeting rooms
- ✅ Export post-mortems
- ✅ Sync documentation
- ✅ Embed meeting links

**Architecture Support**: **PERFECT FIT**

Video meetings are workflow steps:
```ruby
# app/workflows/incident_creation_workflow.rb
class IncidentCreationWorkflow < Workflows::Base
  def define
    step :create_slack_channel
    step :create_video_meeting  # ← Integration point
    step :create_postmortem_doc # ← Integration point
    step :notify_responders
  end

  def create_video_meeting(workflow:, step:, input:)
    incident = workflow.subject
    integration = incident.workspace.integrations.video.active.first

    case integration&.integration_type
    when "zoom"
      ZoomClient.new(integration).create_meeting(
        topic: "Incident: #{incident.name}",
        start_time: Time.current
      )
    when "google_meet"
      GoogleMeetClient.new(integration).create_meeting(
        summary: incident.name
      )
    when "microsoft_teams"
      TeamsClient.new(integration).create_meeting(
        subject: incident.name
      )
    end
  end
end
```

### 5. HR Systems (7 integrations)
**Platforms**: BambooHR, CharlieHR, HiBob, Google Calendar, etc.

**Capabilities Required**:
- ✅ Import PTO/time-off calendars
- ✅ Check on-call availability
- ✅ Sync team rosters
- ✅ Update on-call schedules

**Architecture Support**: **PERFECT FIT**

Scheduled sync workflows:
```ruby
# app/workflows/integrations/hr_calendar_sync_workflow.rb
class Integrations::HRCalendarSyncWorkflow < Workflows::Base
  def define
    step :fetch_time_off_data
    step :update_user_availability
    step :recalculate_oncall_schedules
  end
end

# Scheduled job
# Runs every 6 hours
class HRCalendarSyncJob < ApplicationJob
  def perform
    Integration.hr_systems.active.each do |integration|
      Integrations::HRCalendarSyncWorkflow.start!(integration)
    end
  end
end
```

### 6. Cloud & Infrastructure (13 integrations)
**Platforms**: AWS, Azure, GCP, Cloudflare, Statuspage, Salesforce, etc.

**Capabilities Required**:
- ✅ Trigger cloud actions (scaling, failover)
- ✅ Update status pages
- ✅ Fetch infrastructure metadata
- ✅ Execute runbooks

**Architecture Support**: **PERFECT FIT**

These are runbook workflows:
```ruby
# app/workflows/runbooks/aws_scale_up_workflow.rb
class Runbooks::AWSScaleUpWorkflow < Workflows::Base
  def define
    step :validate_aws_credentials
    step :get_current_capacity
    step :calculate_target_capacity
    step :update_auto_scaling_group
    step :wait_for_healthy_instances
    step :verify_scaling
  end
end
```

---

## Integration Framework Architecture

### Core Abstraction: Integration Registry

```ruby
# config/initializers/integrations.rb
module Integrations
  class Registry
    CATEGORIES = {
      issue_tracking: %w[jira linear github gitlab asana clickup shortcut zendesk],
      service_catalog: %w[backstage cortex opslevel servicenow],
      alerting: %w[datadog pagerduty grafana newrelic sentry prometheus splunk],
      video: %w[zoom google_meet microsoft_teams],
      documentation: %w[confluence google_docs notion],
      hr_systems: %w[bamboohr charliehr hibob google_calendar],
      cloud: %w[aws azure gcp cloudflare],
      status_pages: %w[statuspage],
      communication: %w[slack microsoft_teams]
    }.freeze

    def self.all
      CATEGORIES.values.flatten
    end

    def self.for_category(category)
      CATEGORIES[category.to_sym]
    end

    def self.metadata_for(integration_type)
      const_get("#{integration_type.camelize}::Metadata").new
    rescue NameError
      raise "Integration #{integration_type} not registered"
    end
  end
end
```

### Integration Metadata (Self-Describing)

```ruby
# app/integrations/jira/metadata.rb
module Integrations
  module Jira
    class Metadata
      def name
        "Jira"
      end

      def category
        :issue_tracking
      end

      def description
        "Export and automatically sync your incident actions with tickets in Jira"
      end

      def capabilities
        %i[
          create_ticket
          update_ticket
          bi_directional_sync
          link_to_incident
          custom_fields
          status_mapping
        ]
      end

      def required_credentials
        {
          url: { type: :string, description: "Jira instance URL" },
          username: { type: :string, description: "Jira username" },
          api_token: { type: :password, description: "Jira API token" }
        }
      end

      def required_config
        {
          project_key: { type: :string, description: "Default Jira project key" },
          issue_type: { type: :select, options: ["Bug", "Task", "Story"], default: "Task" }
        }
      end

      def workflow_class
        "Integrations::JiraSyncWorkflow"
      end

      def client_class
        "Integrations::Jira::Client"
      end

      def ai_capabilities
        {
          create_ticket: {
            description: "Create a Jira ticket",
            parameters: [:summary, :description, :project, :issue_type, :priority],
            natural_language_examples: [
              "create a jira ticket for this incident",
              "make a jira issue in the INFRA project",
              "open a ticket about the database slowdown"
            ]
          },
          update_ticket: {
            description: "Update an existing Jira ticket",
            parameters: [:ticket_key, :status, :comment],
            natural_language_examples: [
              "update the jira ticket with the resolution",
              "mark the jira issue as done"
            ]
          }
        }
      end
    end
  end
end
```

### Integration Client (Standardized Interface)

```ruby
# app/integrations/base_client.rb
module Integrations
  class BaseClient
    attr_reader :integration

    def initialize(integration)
      @integration = integration
      @credentials = decrypt_credentials
      @config = integration.config
    end

    # Standard interface all clients must implement
    def test_connection
      raise NotImplementedError
    end

    def create_ticket(incident:, **options)
      raise NotImplementedError
    end

    def update_ticket(ticket_id:, **changes)
      raise NotImplementedError
    end

    def get_ticket(ticket_id:)
      raise NotImplementedError
    end

    def sync_from_external
      raise NotImplementedError
    end

    private

    def decrypt_credentials
      # Use Rails encrypted credentials
      ActiveSupport::MessageEncryptor.new(
        Rails.application.credentials.secret_key_base[0..31]
      ).decrypt_and_verify(@integration.encrypted_credentials)
    end

    def handle_rate_limit(response)
      if response.status == 429
        retry_after = response.headers["Retry-After"]&.to_i || 60
        sleep(retry_after)
        retry
      end
    end

    def handle_errors
      yield
    rescue StandardError => e
      Rails.logger.error("Integration error: #{e.message}")
      record_integration_event("error", error: e.message)
      raise
    end

    def record_integration_event(event_type, **metadata)
      @integration.integration_events.create!(
        event_type: "#{@integration.integration_type}.#{event_type}",
        metadata: metadata
      )
    end
  end
end
```

### Jira Client Example

```ruby
# app/integrations/jira/client.rb
module Integrations
  module Jira
    class Client < BaseClient
      def test_connection
        handle_errors do
          response = connection.get("/rest/api/3/myself")
          response.success?
        end
      end

      def create_ticket(incident:, project: nil, issue_type: nil, **options)
        handle_errors do
          project ||= @config["project_key"]
          issue_type ||= @config["issue_type"] || "Task"

          response = connection.post("/rest/api/3/issue") do |req|
            req.body = {
              fields: {
                project: { key: project },
                summary: incident.name,
                description: format_description(incident),
                issuetype: { name: issue_type },
                priority: { name: severity_to_priority(incident.severity) },
                labels: ["firefight", "incident", incident.severity]
              }
            }.to_json
          end

          ticket_data = JSON.parse(response.body)

          record_integration_event("ticket_created",
            ticket_key: ticket_data["key"],
            ticket_url: "#{@credentials[:url]}/browse/#{ticket_data['key']}"
          )

          ticket_data
        end
      end

      def update_ticket(ticket_key:, **changes)
        handle_errors do
          response = connection.put("/rest/api/3/issue/#{ticket_key}") do |req|
            req.body = {
              fields: changes
            }.to_json
          end

          record_integration_event("ticket_updated", ticket_key: ticket_key)

          true
        end
      end

      def sync_from_external
        handle_errors do
          since = @integration.last_synced_at || 1.hour.ago

          # Search for tickets updated since last sync
          jql = "project = #{@config['project_key']} AND labels = firefight AND updated > '#{since.strftime('%Y-%m-%d %H:%M')}'"

          response = connection.get("/rest/api/3/search") do |req|
            req.params = { jql: jql, fields: "summary,status,updated" }
          end

          tickets = JSON.parse(response.body)["issues"]

          tickets.each do |ticket|
            sync_ticket_to_incident(ticket)
          end

          @integration.update!(last_synced_at: Time.current)
        end
      end

      private

      def connection
        @connection ||= Faraday.new(url: @credentials[:url]) do |f|
          f.request :authorization, :basic, @credentials[:username], @credentials[:api_token]
          f.request :json
          f.response :json
          f.response :raise_error
          f.adapter Faraday.default_adapter
        end
      end

      def format_description(incident)
        {
          type: "doc",
          version: 1,
          content: [
            {
              type: "paragraph",
              content: [
                { type: "text", text: incident.summary }
              ]
            },
            {
              type: "paragraph",
              content: [
                { type: "text", text: "Incident URL: " },
                { type: "text", text: incident.url, marks: [{ type: "link", attrs: { href: incident.url } }] }
              ]
            }
          ]
        }
      end

      def severity_to_priority(severity)
        {
          "critical" => "Highest",
          "major" => "High",
          "minor" => "Medium"
        }[severity] || "Low"
      end

      def sync_ticket_to_incident(ticket)
        # Find incident linked to this ticket
        incident = Incident.find_by(
          "platform_data->>'jira_ticket_key' = ?", ticket["key"]
        )

        return unless incident

        # Sync status if changed
        jira_status = ticket["fields"]["status"]["name"]
        incident_status = jira_status_to_incident_status(jira_status)

        if incident_status && incident.status != incident_status
          incident.update_status!(
            incident_status,
            by: "jira_sync",
            reason: "Synced from Jira ticket #{ticket['key']}"
          )
        end
      end

      def jira_status_to_incident_status(jira_status)
        {
          "To Do" => "declared",
          "In Progress" => "investigating",
          "Done" => "resolved"
        }[jira_status]
      end
    end
  end
end
```

### Integration Workflow (Orchestration)

```ruby
# app/workflows/integrations/jira_sync_workflow.rb
class Integrations::JiraSyncWorkflow < Workflows::Base
  def define
    step :validate_integration
    step :create_or_update_jira_ticket
    step :add_incident_link
    step :sync_watchers
    step :update_incident_platform_data
  end

  private

  def validate_integration(workflow:, step:, input:)
    incident = workflow.subject
    integration = incident.workspace.integrations.jira.active.first

    raise "No active Jira integration" unless integration

    client = Integrations::Jira::Client.new(integration)
    raise "Jira connection failed" unless client.test_connection

    { integration: integration, client: client }
  end

  def create_or_update_jira_ticket(workflow:, step:, input:)
    incident = workflow.subject
    client = input[:client]

    # Check if ticket already exists
    if incident.platform_data["jira_ticket_key"]
      # Update existing ticket
      client.update_ticket(
        ticket_key: incident.platform_data["jira_ticket_key"],
        summary: incident.name,
        description: incident.summary,
        priority: client.send(:severity_to_priority, incident.severity)
      )

      { ticket_key: incident.platform_data["jira_ticket_key"], action: "updated" }
    else
      # Create new ticket
      ticket_data = client.create_ticket(
        incident: incident,
        project: input[:project],
        issue_type: input[:issue_type]
      )

      { ticket_key: ticket_data["key"], ticket_url: ticket_data["self"], action: "created" }
    end
  end

  def add_incident_link(workflow:, step:, input:)
    incident = workflow.subject
    client = input[:client]

    # Add remote link from Jira ticket to incident
    client.connection.post("/rest/api/3/issue/#{input[:ticket_key]}/remotelink") do |req|
      req.body = {
        object: {
          url: incident.url,
          title: "View incident in FireFight",
          icon: {
            url16x16: "https://firefight.dev/favicon.ico"
          }
        }
      }.to_json
    end

    {}
  end

  def sync_watchers(workflow:, step:, input:)
    incident = workflow.subject
    client = input[:client]

    # Add incident responders as watchers
    incident.responders.each do |responder|
      jira_user = find_jira_user_by_email(client, responder.email)
      next unless jira_user

      client.connection.post("/rest/api/3/issue/#{input[:ticket_key]}/watchers") do |req|
        req.body = jira_user["accountId"]
      end
    end

    {}
  end

  def update_incident_platform_data(workflow:, step:, input:)
    incident = workflow.subject

    incident.update!(
      platform_data: incident.platform_data.merge(
        "jira_ticket_key" => input[:ticket_key],
        "jira_ticket_url" => input[:ticket_url],
        "jira_synced_at" => Time.current.iso8601
      )
    )

    {}
  end
end
```

---

## AI-Powered Natural Language Integration

### Architecture: Intent Recognition → Parameter Extraction → Workflow Execution

```ruby
# app/services/ai/intent_recognition_service.rb
class AI::IntentRecognitionService
  def recognize(text:, context:)
    # Use LLM to extract intent and parameters
    response = OpenAI::ChatService.complete(
      model: "gpt-4",
      messages: [
        {
          role: "system",
          content: build_system_prompt(context)
        },
        {
          role: "user",
          content: text
        }
      ],
      tools: available_integration_tools(context.workspace),
      tool_choice: "auto"
    )

    parse_tool_calls(response)
  end

  private

  def build_system_prompt(context)
    <<~PROMPT
      You are FireFight AI, an incident management assistant.

      Current context:
      - User: #{context.user.name} (#{context.user.email})
      - Workspace: #{context.workspace.name}
      - Current incident: #{context.incident&.name || "None"}

      Available integrations:
      #{list_active_integrations(context.workspace)}

      Your job is to understand the user's intent and call the appropriate integration tool.
      Always extract all necessary parameters from the user's message or context.
      If parameters are missing, ask for clarification.
    PROMPT
  end

  def available_integration_tools(workspace)
    tools = []

    workspace.integrations.active.each do |integration|
      metadata = Integrations::Registry.metadata_for(integration.integration_type)

      metadata.ai_capabilities.each do |capability_name, capability_info|
        tools << {
          type: "function",
          function: {
            name: "#{integration.integration_type}_#{capability_name}",
            description: capability_info[:description],
            parameters: {
              type: "object",
              properties: build_parameters_schema(capability_info[:parameters]),
              required: capability_info[:parameters]
            }
          }
        }
      end
    end

    # Add generic tools
    tools << {
      type: "function",
      function: {
        name: "ask_for_clarification",
        description: "Ask the user for more information when parameters are unclear",
        parameters: {
          type: "object",
          properties: {
            question: { type: "string", description: "Question to ask the user" }
          },
          required: ["question"]
        }
      }
    }

    tools
  end

  def build_parameters_schema(parameters)
    schema = {}

    parameters.each do |param|
      schema[param] = {
        type: "string",
        description: "#{param.to_s.humanize} extracted from user message or context"
      }
    end

    schema
  end

  def list_active_integrations(workspace)
    workspace.integrations.active.map do |integration|
      metadata = Integrations::Registry.metadata_for(integration.integration_type)
      "- #{metadata.name} (#{integration.integration_type}): #{metadata.description}"
    end.join("\n")
  end

  def parse_tool_calls(response)
    tool_calls = response.dig("choices", 0, "message", "tool_calls")
    return [] unless tool_calls

    tool_calls.map do |tool_call|
      {
        integration_type: tool_call["function"]["name"].split("_").first,
        action: tool_call["function"]["name"].split("_")[1..].join("_"),
        parameters: JSON.parse(tool_call["function"]["arguments"])
      }
    end
  end
end
```

### AI Command Handler

```ruby
# app/commands/ai_command.rb
class Commands::AICommand < Commands::Base
  # /ff <natural language command>

  def call
    context = build_context

    # Recognize intent
    intents = AI::IntentRecognitionService.new.recognize(
      text: params[:text],
      context: context
    )

    # Handle clarification requests
    if intents.first[:action] == "ask_for_clarification"
      post_ephemeral(text: intents.first[:parameters]["question"])
      return
    end

    # Execute integrations
    results = execute_intents(intents, context)

    # Format response
    post_ephemeral(blocks: format_results(results))
  end

  private

  def build_context
    OpenStruct.new(
      user: current_user,
      workspace: workspace,
      incident: current_incident,
      channel: params[:channel_id]
    )
  end

  def execute_intents(intents, context)
    intents.map do |intent|
      execute_integration_action(
        integration_type: intent[:integration_type],
        action: intent[:action],
        parameters: intent[:parameters],
        context: context
      )
    end
  end

  def execute_integration_action(integration_type:, action:, parameters:, context:)
    integration = workspace.integrations.find_by(integration_type: integration_type, status: "active")

    raise "#{integration_type} integration not configured" unless integration

    case action
    when "create_ticket"
      create_ticket(integration, parameters, context)
    when "update_ticket"
      update_ticket(integration, parameters, context)
    # ... other actions
    end
  end

  def create_ticket(integration, params, context)
    incident = context.incident || find_incident_from_context(context)

    # Start integration workflow with AI-extracted parameters
    workflow = Integrations.const_get("#{integration.integration_type.camelize}SyncWorkflow").start!(
      incident,
      input: {
        project: params["project"],
        issue_type: params["issue_type"],
        priority: params["priority"]
      }
    )

    # Wait for workflow to complete (or timeout)
    workflow.reload until workflow.completed? || workflow.failed?

    if workflow.succeeded?
      ticket_key = incident.reload.platform_data["#{integration.integration_type}_ticket_key"]
      ticket_url = incident.platform_data["#{integration.integration_type}_ticket_url"]

      {
        success: true,
        message: "Created #{integration.integration_type} ticket: #{ticket_key}",
        url: ticket_url
      }
    else
      {
        success: false,
        message: "Failed to create ticket: #{workflow.workflow_steps.failed.first&.last_error}"
      }
    end
  end

  def format_results(results)
    blocks = [
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: "*FireFight AI executed your request:*"
        }
      }
    ]

    results.each do |result|
      blocks << {
        type: "section",
        text: {
          type: "mrkdwn",
          text: result[:success] ? "✅ #{result[:message]}" : "❌ #{result[:message]}"
        }
      }

      if result[:url]
        blocks << {
          type: "actions",
          elements: [
            {
              type: "button",
              text: { type: "plain_text", text: "View" },
              url: result[:url]
            }
          ]
        }
      end
    end

    blocks
  end
end
```

### Example AI Interactions

```
User: /ff create a jira ticket for this incident in the INFRA project

AI Processing:
1. Extract intent: create_ticket
2. Extract integration: jira
3. Extract parameters:
   - incident: (from channel context)
   - project: "INFRA"
   - issue_type: (use default from config)
4. Execute: Integrations::JiraSyncWorkflow.start!(incident, project: "INFRA")
5. Respond: "✅ Created Jira ticket: INFRA-123"

---

User: /ff notify the team and create tracking tickets

AI Processing:
1. Extract multiple intents:
   - notify_team (Slack)
   - create_ticket (multiple integrations)
2. Execute in parallel:
   - Post Slack notification
   - Create Jira ticket
   - Create Linear issue
3. Respond:
   "✅ Notified #oncall channel
    ✅ Created Jira ticket: INFRA-123
    ✅ Created Linear issue: ENG-456"

---

User: /ff sync this to our docs

AI Processing:
1. Recognize ambiguity - which documentation system?
2. Check active integrations: Confluence, Notion
3. Call: ask_for_clarification
4. Respond: "I found 2 documentation integrations. Which one?
   - Confluence (Team Wiki)
   - Notion (Engineering Docs)"

User: notion

AI Processing:
1. Intent: create_document
2. Integration: notion
3. Execute: Integrations::NotionSyncWorkflow.start!(incident)
4. Respond: "✅ Created Notion page: Post-Mortem Draft"
```

---

## Adding New Integrations: Step-by-Step

### Example: Adding Datadog Integration

**Step 1: Create metadata**
```ruby
# app/integrations/datadog/metadata.rb
module Integrations
  module Datadog
    class Metadata
      def name
        "Datadog"
      end

      def category
        :alerting
      end

      def capabilities
        %i[receive_alerts create_incidents acknowledge_alerts resolve_alerts]
      end

      def required_credentials
        {
          api_key: { type: :password },
          application_key: { type: :password }
        }
      end

      def ai_capabilities
        {
          acknowledge_alert: {
            description: "Acknowledge a Datadog alert",
            parameters: [:alert_id],
            natural_language_examples: [
              "acknowledge the datadog alert",
              "ack the alert"
            ]
          }
        }
      end
    end
  end
end
```

**Step 2: Create client**
```ruby
# app/integrations/datadog/client.rb
module Integrations
  module Datadog
    class Client < BaseClient
      def test_connection
        handle_errors do
          response = connection.get("/api/v1/validate")
          response.success?
        end
      end

      def acknowledge_alert(alert_id:)
        handle_errors do
          connection.post("/api/v1/monitor/#{alert_id}/mute")
        end
      end

      # ... other methods
    end
  end
end
```

**Step 3: Create workflow (optional)**
```ruby
# app/workflows/integrations/datadog_sync_workflow.rb
class Integrations::DatadogSyncWorkflow < Workflows::Base
  def define
    step :acknowledge_alert_in_datadog
    step :add_incident_tag
  end
end
```

**Step 4: Create webhook receiver**
```ruby
# app/controllers/api/v1/webhooks/datadog_controller.rb
class Api::V1::Webhooks::DatadogController < Api::BaseController
  def create
    alert = parse_datadog_webhook(params)

    incident = Incident.create_from_datadog_alert!(
      workspace: workspace,
      alert: alert
    )

    IncidentCreationWorkflow.start!(incident)

    render json: { incident_id: incident.id }
  end
end
```

**Step 5: Register in registry**
```ruby
# config/initializers/integrations.rb
module Integrations
  class Registry
    CATEGORIES = {
      # ...
      alerting: %w[datadog pagerduty grafana newrelic], # ← Add here
      # ...
    }
  end
end
```

**That's it! 5 files, no database changes.**

The AI system automatically picks up the new integration through the metadata's `ai_capabilities`.

---

## Integration Support Matrix

| Category | Integrations | Architecture Support | Difficulty | Estimated Time per Integration |
|----------|--------------|---------------------|------------|-------------------------------|
| **Issue Tracking** | Jira, Linear, GitHub, GitLab, Asana, ClickUp, Shortcut, Zendesk | ✅ Perfect (workflow-based) | Low | 2-3 days |
| **Service Catalog** | Backstage, Cortex, OpsLevel, ServiceNow | ✅ Perfect (import workflows) | Medium | 3-5 days |
| **Alerting** | Datadog, PagerDuty, Grafana, New Relic, Sentry, etc. | ✅ Perfect (webhook receivers) | Low | 1-2 days |
| **Video** | Zoom, Google Meet, Teams | ✅ Perfect (workflow steps) | Low | 1-2 days |
| **Documentation** | Confluence, Google Docs, Notion | ✅ Perfect (export workflows) | Medium | 2-4 days |
| **HR Systems** | BambooHR, CharlieHR, etc. | ✅ Perfect (scheduled sync) | Medium | 3-4 days |
| **Cloud/Infra** | AWS, Azure, GCP, Cloudflare | ✅ Perfect (runbook workflows) | Medium-High | 4-7 days |

**Total to match incident.io**: ~67 integrations × 3 days avg = **200 days** (can be parallelized!)

**With your architecture**: Adding each new integration is **mechanical, not architectural**.

---

## AI Layer Benefits

### 1. No Learning Curve for Users
```
❌ User needs to remember: /ff create-ticket --integration jira --project INFRA
✅ User just says: /ff create a jira ticket in INFRA
```

### 2. Context-Aware
```
User is in incident channel #inc-database-slowdown

User: /ff create tickets
AI: ✅ Created Jira ticket: INFRA-123 for incident "Database slowdown"
```

### 3. Multi-Integration Orchestration
```
User: /ff escalate this to critical

AI executes:
1. Update incident severity → critical
2. Page on-call via PagerDuty
3. Create P0 Jira ticket
4. Post to #incidents-critical Slack channel
5. Start Zoom meeting
6. Update Statuspage
```

### 4. Learning System
```ruby
# Store successful AI executions
class AIExecution < ApplicationRecord
  belongs_to :workspace

  # text: "create a jira ticket for this incident"
  # intent: { integration: "jira", action: "create_ticket" }
  # parameters: { project: "INFRA" }
  # success: true
end

# Use for fine-tuning or few-shot learning
def build_system_prompt(context)
  recent_successes = AIExecution.where(workspace: context.workspace, success: true)
    .order(created_at: :desc)
    .limit(5)

  examples = recent_successes.map do |exec|
    "User: #{exec.text}\nAction: #{exec.intent} with #{exec.parameters}"
  end.join("\n\n")

  "Here are recent successful commands:\n#{examples}"
end
```

---

## Migration Strategy

### Phase 1: Core Integration Framework (Week 1-2)
- [ ] Create `integrations` table
- [ ] Create `integration_events` table
- [ ] Build `BaseClient` abstraction
- [ ] Build `Registry` system
- [ ] Add encrypted credentials support

### Phase 2: First 3 Integrations (Week 3-4)
- [ ] Jira (issue tracking)
- [ ] Slack (communication) - already partially done
- [ ] PagerDuty (alerting)

**Why these 3?** They cover 3 different patterns:
- Jira = bi-directional sync
- Slack = outbound messaging
- PagerDuty = inbound webhooks

### Phase 3: AI Layer (Week 5-6)
- [ ] Intent recognition service
- [ ] Parameter extraction
- [ ] AI command handler
- [ ] Tool calling with OpenAI
- [ ] Context awareness

### Phase 4: Scale to 20 integrations (Week 7-16)
- [ ] 5 more issue tracking (Linear, GitHub, GitLab, Asana, ClickUp)
- [ ] 5 alerting (Datadog, Grafana, New Relic, Sentry, Prometheus)
- [ ] 3 video (Zoom, Google Meet, Teams)
- [ ] 3 documentation (Confluence, Notion, Google Docs)
- [ ] 2 service catalog (Backstage, OpsLevel)
- [ ] 2 cloud (AWS, GCP)

### Phase 5: Long Tail (Week 17+)
- [ ] Remaining 47 integrations
- [ ] Can be added incrementally based on customer demand
- [ ] Community contributions (if open source)

---

## Competitive Advantage

### incident.io
- ✅ Has 67 integrations
- ❌ No AI-powered natural language
- ❌ Closed source
- ❌ Complex pricing

### FireFight
- 🔄 Start with 20 integrations, scale to 67+
- ✅ AI-powered natural language ("create a jira ticket")
- ✅ Open source potential
- ✅ Simpler architecture (easier to maintain)
- ✅ Integration framework makes adding new ones trivial

---

## Conclusion

**YES - Your architecture can support ALL 67+ integrations.**

More importantly:

1. **Adding integrations is mechanical**: 5 files per integration, no database changes
2. **AI makes integrations invisible**: Users don't need to learn syntax
3. **Workflow system = integration orchestration**: Multi-step integrations are workflows
4. **Event system = webhook foundation**: Outbound webhooks are automatic
5. **Polymorphic design = flexibility**: Any entity can integrate with anything

Your architecture is **better positioned** than incident.io's because:
- Workflow orchestration is more flexible than hardcoded integrations
- AI layer provides better UX than command-line flags
- Event-driven design makes webhooks natural
- Open architecture allows community integrations

**Focus on building the integration framework first, then add integrations incrementally based on customer demand.**

Start with Jira, PagerDuty, and Slack. Get those perfect. The rest will follow the same pattern.
