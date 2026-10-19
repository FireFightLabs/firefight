require "active_support/testing/time_helpers"

# The Acme workspace the README's dashboard pictures show, built the way production writes it: the incident through
# IncidentLifecycleService, its alert through the Datadog adapter and AlertIngestService, Halon's run through
# InvestigationService and its own records, and the chat through Conversation. So every name on the page, Halon and
# Firefight among them, is the one current code gives.
#
# Nothing it starts runs. Jobs are held while it builds and the platform runs the incident starts are cancelled, so no
# message reaches Slack and no model is called. The incident's channel is written last, as the one Slack made for it,
# so nothing tries to post there while the story is built.
module Demo
  class ReadmeWorkspace
    include ActiveSupport::Testing::TimeHelpers

    NAME = "Acme".freeze
    # The team a real install would connect. Its id finds the workspace again, so a second run replaces it.
    TEAM_ID = "T0ACMEDEMO".freeze
    LEAD = { name: "Maya Ortiz", email: "maya@acme.dev" }.freeze
    COMMUNICATIONS = { name: "Priya Shah", email: "priya@acme.dev" }.freeze
    OPERATIONS = { name: "Sam Lee", email: "sam@acme.dev" }.freeze
    ROLES = {
      communications: { name: "Communications Lead", description: "Keeps customers and the rest of the company told how the incident stands." },
      operations: { name: "Ops Lead", description: "Runs the changes to the systems the incident touches." }
    }.freeze

    NUMBER = 42
    CHANNEL_ID = "C0ACMEINC42".freeze
    PRODUCTION = Workspace::IncidentDefaults::DEFAULT_TYPES.first.fetch(:slug)
    TITLE = "Checkout failing for card payments".freeze
    DESCRIPTION = "Card payments at checkout return errors for most customers. PayPal and saved wallets still go through.".freeze
    SOURCE_NAME = "Datadog monitors".freeze
    # Datadog's webhook body, filled in the way TEMPLATE fills it for the checkout monitor.
    MONITOR = {
      "alert_cycle_key" => "7310592045823102114", "aggregation_key" => "c41d6e0b8a3f2e17", "monitor_id" => "148203571",
      "transition" => "Triggered", "title" => "[Triggered on {service:checkout-api}] Checkout 5xx rate above 5%",
      "message" => DESCRIPTION, "priority" => "P1", "service" => "checkout-api", "environment" => "production", "team" => "payments",
      "link" => "https://app.datadoghq.com/monitors/148203571"
    }.freeze
    # Fourteen firings, the first once the incident is declared and the last at 14:31.
    FIRINGS = Array.new(14) { |index| [ 14, 6, 5 + (index * 115) ] }.freeze

    QUESTION = "Card payments are failing at checkout since about 14:04. What changed?".freeze
    CHAT_TITLE = "Card payments failing at checkout since 14:04".freeze
    SYMPTOM = "Card payments failing at checkout since 14:04".freeze
    TOOL_CALL_ID = "call_demo_readme_start".freeze
    STARTED = "Started. Tell the person it is running and that its answer will come back here, then stop.".freeze

    DEPLOY_THEORY = "A deploy of checkout-api broke card payments".freeze
    GATEWAY_THEORY = "payments-gateway is failing card authorisations".freeze
    POOL_THEORY = "The 14:02 deploy lowered the database pool, so checkout requests wait for a connection and time out".freeze
    # What Firefight's own map tools would read here. With nothing connected, each goes through the gateway as their map read.
    STEPS = [
      { at: [ 14, 7, 5 ], tool: ResourceMap::Timeline::TOOL_NAME, label: "Deploys of checkout-api in the last hour",
        result: "checkout-api deployed at 14:02 from pull request #812 in acme/checkout. No other deploy in the hour." },
      { at: [ 14, 7, 20 ], tool: Integrations::Capabilities::KEY_QUERY_TOOL, label: "5xx rate on checkout-api, 13:30 to now",
        result: "0.2% until 14:03, then 7.1% from 14:04 and 6.8% now." },
      { at: [ 14, 7, 55 ], tool: Integrations::Capabilities::KEY_QUERY_TOOL, label: "Error rate and latency on payments-gateway",
        result: "Errors 0.1% and p95 latency 210 ms, both flat since 13:30." },
      { at: [ 14, 8, 30 ], tool: Integrations::Capabilities::SPECS.fetch(Integrations::Capabilities::LOGS).tool_name,
        label: "Errors in checkout-api logs since 14:00",
        result: "312 errors since 14:04, every one ActiveRecord::ConnectionTimeoutError: could not obtain a connection from the pool within 5.000 seconds." },
      { at: [ 14, 9, 0 ], tool: ResourceMap::Timeline::TOOL_NAME, label: "Diff of pull request #812 in acme/checkout",
        result: "config/database.yml: pool changed from 20 to 5 for production." }
    ].freeze
    STEP_SECONDS = 4

    WHAT_IS_WRONG = "The 14:02 deploy of checkout-api lowered the database pool from 20 to 5, so checkout requests wait for a " \
                    "connection and time out.".freeze
    SUMMARY = "#{WHAT_IS_WRONG} Card payments hold a connection while they wait on the payments gateway, so they run out " \
              "first. Setting the pool back to 20 ends it.".freeze
    SUGGESTED_FIX = "Open a pull request in acme/checkout that sets the pool back to 20.".freeze
    FIX = {
      "summary" => "Set the database pool back to 20",
      "steps" => [ { "kind" => Investigation::RemediationStep::KIND_PULL_REQUEST, "repository" => "acme/checkout",
                     "description" => "Set pool back to 20 in config/database.yml" } ]
    }.freeze

    # Older chats in the list beside it, as [days before, hour, minute, title, question, answer].
    OLDER_CHATS = [
      [ 4, 11, 30, "Today's checkout-api release", "What went out in today's checkout-api release?",
        "One deploy at 11:20, pull request #806 in acme/checkout, which logs each retry of the payment webhook. Nothing else changed." ],
      [ 1, 16, 20, "Services on orders-db", "Which services use orders-db?",
        "checkout-api and checkout-worker both read and write orders-db. payments-gateway never touches it." ]
    ].freeze

    def self.build!(day: nil) = new(day || story_day).build!

    # The last day the story is already over on this machine's clock, so nothing in it is still to come.
    def self.story_day
      today = Time.now.to_date
      Time.now >= Time.new(today.year, today.month, today.day, 14, 47) ? today : today - 1
    end

    def self.declared_at(day = nil) = new(day || story_day).time(14, 6)

    def initialize(day)
      @day = day
    end

    def time(hour, minute, second = 0, day: @day) = Time.new(day.year, day.month, day.day, hour, minute, 0) + second

    def build!
      holding_jobs do
        ApplicationRecord.transaction do
          Workspace.find_by(platform: Platforms::SLACK, platform_id: TEAM_ID)&.destroy!
          set_up!
          OLDER_CHATS.each { |chat| older_chat!(*chat) }
          declare!
          investigate!
          respond!
          cancel_platform_runs!
          record_channel!
        end
        @workspace
      end
    ensure
      travel_back
    end

    private

    def holding_jobs
      adapter = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      yield
    ensure
      ActiveJob::Base.queue_adapter = adapter
    end

    def set_up!
      travel_to(time(9, 0, day: @day - 7))
      @lead = Workspace.sign_up!(name: NAME, user: user(LEAD))
      @workspace = @lead.workspace
      @workspace.connect_chat!(platform: Platforms::SLACK, platform_id: TEAM_ID, platform_data: { "name" => NAME })
      finish_setup!
      @communications = join!(COMMUNICATIONS)
      @operations = join!(OPERATIONS)
      @roles = ROLES.transform_values { |role| IncidentRole.create_in_list!(@workspace, role) }
      @critical = @workspace.incident_severities.find_by!(slug: IncidentSeverity::SLUG_CRITICAL)
      @source = @workspace.alert_sources.create!(name: SOURCE_NAME, provider: AlertSource::PROVIDER_DATADOG)
      @routing = @source.find_or_create_alert_routing_policy!
      @routing.policy_rules.create!(
        priority: 1, conditions: [], outcome: { "action" => AlertIngestService::ACTION_AUTO_CREATE, "severity_id" => @critical.id }
      )
      @routing.update!(enabled: true)
      @source.reload
    end

    # Acme has run incidents for a while, so its setup is long behind it. Its steps need an AI account and connections a
    # demo has none of, so the checklist is stamped finished rather than worked through.
    def finish_setup!
      onboarding = @workspace.onboarding
      onboarding.founder_letter_seen!
      onboarding.dismiss_dialog!
      onboarding.update!(checklist_completed_at: Time.current)
    end

    def user(person)
      User.find_or_create_by!(email: person[:email]) { |created| created.name = person[:name] }
    end

    def join!(person)
      @workspace.invitations.create!(email: person[:email], invited_by: @lead, last_sent_at: Time.current).accept!(user(person))
    end

    def older_chat!(days_before, hour, minute, title, question, answer)
      travel_to(time(hour, minute, day: @day - days_before))
      conversation = Conversation.start_personal!(workspace: @workspace, member: @lead)
      conversation.ask!(question, asker: @lead)
      travel_to(time(hour, minute, 20, day: @day - days_before))
      conversation.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: answer)
      conversation.reply_delivered!
      conversation.rename!(title)
    end

    # The incident goes in at its own number, so the alert joins it the way a storm's later alerts join the incident
    # the first one declared. Its routing rule would have declared it.
    def declare!
      travel_to(time(14, 6))
      @incident = lifecycle.create(
        declared_by: nil, incident_status: @workspace.incident_statuses.default_status, incident_severity: @critical,
        name: TITLE, summary: DESCRIPTION, source: Incident::SOURCE_ALERT, sequence_number: NUMBER
      )
      IncidentCreationService.new(@workspace).create_incident_event(@incident)
      AlertGroup.create!(
        workspace: @workspace, incident: @incident, content_signature: AlertGroup.signature_for(monitor_fields, @routing.content_match_fields),
        window_expires_at: Time.current + @routing.grouping_window_minutes.minutes
      )
      FIRINGS.each_with_index do |(hour, minute, second), index|
        travel_to(time(hour, minute, second))
        deliver_alert!(index)
      end
    end

    def monitor_fields = AlertProviders.for(@source.provider).normalize(MONITOR, source: @source).first[:fields]

    def deliver_alert!(index)
      payload = MONITOR.merge("id" => "#{MONITOR['monitor_id']}-#{index + 1}")
      AlertProviders.for(@source.provider).normalize(payload, source: @source).each do |item|
        AlertIngestService.new(@source).ingest(item[:fields], item[:payload])
      end
    end

    # Maya asks in the chat, the chat starts the run, and the run works as InvestigationJob would have it work.
    def investigate!
      travel_to(time(14, 6, 20))
      @conversation = Conversation.start_personal!(workspace: @workspace, member: @lead, subject: @incident)
      @conversation.ask!(QUESTION, asker: @lead)
      @conversation.rename!(CHAT_TITLE)

      travel_to(time(14, 6, 21))
      reply = @conversation.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
      reply.ruby_llm_tool_calls.create!(tool_call_id: TOOL_CALL_ID, name: FirefightTools::START_INVESTIGATION,
                                        arguments: { Investigation::Brief::KEY_SYMPTOM => SYMPTOM })
      run = InvestigationService.new(@workspace).start(
        @incident, trigger_source: Investigation::TRIGGER_CONVERSATION, triggered_by: @lead,
        brief: Investigation::Brief.from({ Investigation::Brief::KEY_SYMPTOM => SYMPTOM }, source: Investigation::Brief::SOURCE_CHAT),
        conversation: @conversation, tool_call_id: TOOL_CALL_ID
      )
      @conversation.chat.add_message(role: :tool, content: STARTED, tool_call_id: TOOL_CALL_ID)
      @conversation.reply_delivered!

      # A worker's claim stamps the database's clock, so the run's start is written on the story's own.
      travel_to(time(14, 6, 30))
      run.update!(status: Investigation::STATUS_RUNNING, started_at: Time.current)
      delivery = Investigation::Delivery.for(run)
      delivery.start!
      work!(run)

      travel_to(time(14, 10, 47))
      finding = run.conclude!(
        summary: SUMMARY, hypothesis_assertion: POOL_THEORY, fix: FIX,
        evidence: [
          { claim: "checkout-api deployed pull request #812 at 14:02, and 5xx errors began at 14:04", steps: [ 1, 2 ] },
          { claim: "Every failing request times out waiting for a database connection", steps: [ 4 ] },
          { claim: "Pull request #812 lowered the pool in config/database.yml from 20 to 5", steps: [ 5 ] }
        ],
        short: { answer_kind: Investigation::Finding::KIND_ROOT_CAUSE, confidence: 0.93, what_is_wrong: WHAT_IS_WRONG,
                 suggested_fix: SUGGESTED_FIX }
      )
      delivery.answered!(finding)
      run.finish!(status: Investigation::STATUS_SUCCEEDED)
      @fix = finding.remediation_plan
    end

    def work!(run)
      theory!(run, [ 14, 7, 0 ], DEPLOY_THEORY)
      step!(run, STEPS[0])
      step!(run, STEPS[1])
      theory!(run, [ 14, 7, 35 ], DEPLOY_THEORY, status: Investigation::Hypothesis::STATUS_SUPPORTED, confidence: 0.8, steps: [ 1, 2 ])
      theory!(run, [ 14, 7, 45 ], GATEWAY_THEORY)
      step!(run, STEPS[2])
      theory!(run, [ 14, 8, 10 ], GATEWAY_THEORY, status: Investigation::Hypothesis::STATUS_REFUTED, steps: [ 3 ])
      theory!(run, [ 14, 8, 20 ], POOL_THEORY)
      step!(run, STEPS[3])
      step!(run, STEPS[4])
      theory!(run, [ 14, 9, 40 ], POOL_THEORY, status: Investigation::Hypothesis::STATUS_SUPPORTED, confidence: 0.93, steps: [ 1, 4, 5 ])
    end

    def theory!(run, clock, assertion, **settled)
      travel_to(time(*clock))
      run.record_hypothesis!(assertion: assertion, **settled)
    end

    def step!(run, step)
      travel_to(time(*step[:at]))
      run.tool_call(action_key: Ability::Action::MAP_READ, tool_name: step[:tool], label: step[:label]) do
        travel_to(time(*step[:at]) + STEP_SECONDS)
        step[:result]
      end
    end

    # Maya applies the fix, takes the lead, marks the cause identified and hands out the roles. Sam and Priya follow.
    def respond!
      travel_to(time(14, 12, 10))
      @fix.apply!(by: @lead, from: AbilityGateway::SOURCE_WEB)

      travel_to(time(14, 13))
      lifecycle.change_status(
        @incident, { incident_status: @workspace.incident_statuses.find_by!(slug: IncidentStatus::SLUG_IDENTIFIED),
                     incident_type: @workspace.incident_types.find_by!(slug: PRODUCTION), lead: @lead },
        changed_by: @lead
      )

      travel_to(time(14, 14))
      lifecycle.assign_roles(@incident, { @roles[:communications] => @communications, @roles[:operations] => @operations }, changed_by: @lead)

      travel_to(time(14, 14, 30))
      @incident.subscribe!(@operations)
      travel_to(time(14, 15))
      @incident.subscribe!(@communications)
    end

    # Each would speak in Slack, which this workspace only pretends to be connected to.
    def cancel_platform_runs!
      SolidWorkflow::Workflow.live.where(subject: @incident).find_each do |run|
        run.cancel!(reason: "The demo workspace is not connected to Slack.", by: "demo:readme")
      end
    end

    # What IncidentCreationService#create_channel writes from Slack's answer when the incident is declared.
    def record_channel!
      @incident.update!(channel_id: CHANNEL_ID, channel_name: @incident.generated_channel_name)
    end

    def lifecycle = @lifecycle ||= IncidentLifecycleService.new(@workspace)
  end
end
