module Operator
  # Everything Firefight did for one incident, from every table that records it, in one order. That is the alerts and their
  # routing, the incident's own events, each workflow and its steps, webhook deliveries, failed platform calls in its
  # channel, and Halon's runs. Read only. A failure carries what an operator can do about it.
  class IncidentProcess
    KIND_ALERT = "alert".freeze
    KIND_INCIDENT = "incident".freeze
    KIND_WORKFLOW = "workflow".freeze
    KIND_STEP = "step".freeze
    KIND_WEBHOOK = "webhook".freeze
    KIND_PLATFORM = "platform".freeze
    KIND_HALON = "halon".freeze
    KINDS = [ KIND_ALERT, KIND_INCIDENT, KIND_WORKFLOW, KIND_STEP, KIND_WEBHOOK, KIND_PLATFORM, KIND_HALON ].freeze

    TONE_OK = "ok".freeze
    TONE_INFO = "info".freeze
    TONE_WARN = "warn".freeze
    TONE_BAD = "bad".freeze
    TONE_IDLE = "idle".freeze
    TONES = [ TONE_OK, TONE_INFO, TONE_WARN, TONE_BAD, TONE_IDLE ].freeze

    ENTRY_LIMIT = 300

    # An incident as a list shows it, with how many of its records failed.
    Row = Data.define(:incident, :problems)

    # retry_step_id and redeliver_id name what the operator can act on, and technical is the raw cause, shown folded.
    Entry = Data.define(:key, :at, :kind, :tone, :title, :detail, :technical, :retry_step_id, :redeliver_id)

    def self.problem_counts(incidents)
      ids = incidents.map(&:id)
      return {} if ids.empty?

      steps = WorkflowRuns.failed_steps_by_incident(ids)
      hooks = WebhookDelivery.failed.joins(:incident_event).where(incident_events: { incident_id: ids }).group("incident_events.incident_id").count
      calls = incidents.select(&:channel_id).each_with_object(Hash.new(0)) do |incident, counts|
        counts[incident.id] = PlatformCallFailure.where(workspace_id: incident.workspace_id, channel_id: incident.channel_id).count
      end
      ids.index_with { |id| steps.fetch(id, 0) + hooks.fetch(id, 0) + calls.fetch(id, 0) }
    end

    def initialize(incident)
      @incident = incident
    end

    def entries
      [ *alert_entries, *event_entries, *workflow_entries, *webhook_entries, *platform_entries, *halon_entries ]
        .select(&:at).sort_by { |entry| [ entry.at, entry.key ] }.first(ENTRY_LIMIT)
    end

    def counts
      all = entries
      { records: all.size, problems: all.count { |entry| entry.tone == TONE_BAD } }
    end

    private

    def entry(key:, at:, kind:, tone:, title:, detail: nil, technical: nil, retry_step_id: nil, redeliver_id: nil)
      Entry.new(key:, at:, kind:, tone:, title:, detail:, technical:, retry_step_id:, redeliver_id:)
    end

    def alert_entries
      @incident.alerts.includes(:alert_source).flat_map do |alert|
        received = entry(key: "alert-#{alert.id}", at: alert.received_at, kind: KIND_ALERT, tone: TONE_INFO,
                         title: "Alert received", detail: "#{alert.alert_source.name} · #{alert.title}")
        routed = alert.routed_at && entry(
          key: "route-#{alert.id}", at: alert.routed_at, kind: KIND_ALERT, tone: TONE_OK,
          title: "Routed", detail: "#{alert.routing_state} after #{alert.routing_attempts} #{'attempt'.pluralize(alert.routing_attempts)}"
        )
        [ received, routed ].compact
      end
    end

    def event_entries
      @incident.incident_events.includes(:actor).chronological.map do |event|
        entry(key: "event-#{event.id}", at: event.created_at, kind: KIND_INCIDENT, tone: TONE_OK,
              title: event.description.to_s.upcase_first, detail: event.actor_name)
      end
    end

    def workflow_entries
      WorkflowRuns.for_subject(@incident).flat_map do |workflow|
        started = entry(key: "workflow-#{workflow.id}", at: workflow.created_at, kind: KIND_WORKFLOW, tone: workflow_tone(workflow),
                        title: "#{workflow.workflow_class} #{workflow.state}", detail: "#{workflow.steps.size} steps")
        [ started, *workflow.steps.map { |step| step_entry(workflow, step) } ]
      end
    end

    def step_entry(workflow, step)
      failed = step.failed?
      entry(
        key: "step-#{step.id}", at: step.completed_at || step.started_at || step.created_at, kind: KIND_STEP, tone: step_tone(step),
        title: step.name, detail: step_detail(workflow, step), technical: (step.last_error if failed),
        retry_step_id: (step.id if failed)
      )
    end

    def step_detail(workflow, step)
      took = step.started_at && step.completed_at ? "#{(step.completed_at - step.started_at).round(1)} s" : nil
      attempts = step.attempts.to_i > 1 || step.failed? ? "attempt #{step.attempts} of #{step.max_attempts}" : nil
      [ workflow.workflow_class, step.status, took, attempts, step.skip_reason ].compact_blank.join(" · ")
    end

    def webhook_entries
      WebhookDelivery.joins(:incident_event).where(incident_events: { incident_id: @incident.id }).includes(:webhook).map do |delivery|
        failed = delivery.failed?
        entry(
          key: "delivery-#{delivery.id}", at: delivery.delivered_at || delivery.updated_at, kind: KIND_WEBHOOK,
          tone: failed ? TONE_BAD : (delivery.succeeded? ? TONE_OK : TONE_WARN),
          title: "Webhook #{delivery.event_type}",
          detail: [ URI(delivery.webhook.url.to_s).host, ("HTTP #{delivery.response_code}" if delivery.response_code),
                    "#{delivery.attempts} #{'attempt'.pluralize(delivery.attempts)}", delivery.state ].compact.join(" · "),
          technical: (delivery.error_message if failed), redeliver_id: (delivery.id if failed)
        )
      rescue URI::InvalidURIError
        nil
      end.compact
    end

    def platform_entries
      return [] if @incident.channel_id.blank?

      PlatformCallFailure.where(workspace_id: @incident.workspace_id, channel_id: @incident.channel_id).map do |failure|
        entry(key: "platform-#{failure.id}", at: failure.created_at, kind: KIND_PLATFORM, tone: TONE_BAD,
              title: "#{failure.platform.titleize} #{failure.operation} failed", detail: failure.error_class, technical: failure.message)
      end
    end

    def halon_entries
      @incident.investigations.seen.includes(:finding).flat_map do |run|
        started = entry(key: "halon-#{run.id}", at: run.created_at, kind: KIND_HALON, tone: TONE_INFO, title: "Halon asked",
                        detail: run.question || run.trigger_source)
        ended = run.completed_at && entry(
          key: "halon-end-#{run.id}", at: run.completed_at, kind: KIND_HALON, tone: halon_tone(run),
          title: run.finding ? "Halon answered" : "Halon stopped",
          detail: [ run.finding&.summary || run.stopped_because, "#{run.turns_used} turns", "$#{run.spent_cents}" ].compact.join(" · "),
          technical: (run.error_summary if run.status == Investigation::STATUS_FAILED)
        )
        [ started, ended ].compact
      end
    end

    def workflow_tone(workflow)
      return TONE_BAD if workflow.failed?
      return TONE_IDLE if workflow.cancelled?
      return TONE_WARN if workflow.paused?

      workflow.succeeded? ? TONE_OK : TONE_INFO
    end

    def step_tone(step)
      return TONE_BAD if step.failed?
      return TONE_IDLE if step.skipped? || step.cancelled?
      return TONE_WARN if step.pending?

      step.succeeded? ? TONE_OK : TONE_INFO
    end

    def halon_tone(run)
      return TONE_OK if run.finding
      run.status == Investigation::STATUS_FAILED ? TONE_BAD : TONE_WARN
    end
  end
end
