module Operator
  # Builds the Needs attention list from failures in the window and anything backed up or stuck now. Each item links to
  # its record. Repeats of one failure become one item with a count.
  class Attention
    KIND_WORKFLOW_FAILED = "workflow_failed".freeze
    KIND_WORKFLOW_STUCK = "workflow_stuck".freeze
    KIND_WEBHOOK_FAILING = "webhook_failing".freeze
    KIND_PLATFORM_FAILED = "platform_failed".freeze
    KIND_ALERT_STUCK = "alert_stuck".freeze
    KIND_QUEUE_BACKED_UP = "queue_backed_up".freeze
    KIND_JOBS_FAILED = "jobs_failed".freeze
    KIND_HALON_FAILED = "halon_failed".freeze
    KIND_HALON_LIMIT = "halon_limit".freeze
    KIND_HALON_NOT_POSTED = "halon_not_posted".freeze
    KIND_HALON_STUCK = "halon_stuck".freeze
    KINDS = [
      KIND_WORKFLOW_FAILED, KIND_WORKFLOW_STUCK, KIND_WEBHOOK_FAILING, KIND_PLATFORM_FAILED, KIND_ALERT_STUCK,
      KIND_QUEUE_BACKED_UP, KIND_JOBS_FAILED, KIND_HALON_FAILED, KIND_HALON_LIMIT, KIND_HALON_NOT_POSTED, KIND_HALON_STUCK
    ].freeze

    # The page an item opens.
    TARGET_WORKFLOW = "workflow".freeze
    TARGET_INCIDENT = "incident".freeze
    TARGET_RUN = "run".freeze
    TARGET_FAILED_JOBS = "failed_jobs".freeze
    TARGET_QUEUES = "queues".freeze
    TARGETS = [ TARGET_WORKFLOW, TARGET_INCIDENT, TARGET_RUN, TARGET_FAILED_JOBS, TARGET_QUEUES ].freeze

    # Stop reasons worth tuning. The other reasons are a person's choice or the model ending without an answer.
    TUNING_LIMITS = [ Investigation::BUDGET_SPENT, Investigation::TOO_MANY_TURNS ].freeze

    # An alert still waiting for routing this long after it arrived counts as stuck.
    ALERT_STUCK_AFTER = 5.minutes
    PER_KIND = 10

    Item = Data.define(:key, :kind, :tone, :title, :subject, :place, :detail, :at, :target, :target_id)

    def initialize(filter, jobs:)
      @filter = filter
      @jobs = jobs
    end

    # Kinds that reached PER_KIND, so the page can say the list is cut.
    def capped_kinds
      items.group_by(&:kind).select { |_kind, group| group.size >= PER_KIND }.keys
    end

    def items
      @items ||= [
        *workflow_items, *webhook_items, *platform_items, *alert_items, *job_items, *halon_items
      ].sort_by { |item| [ item.tone == IncidentProcess::TONE_BAD ? 0 : 1, -item.at.to_f ] }
    end

    private

    def item(key:, kind:, title:, subject:, at:, target:, tone: IncidentProcess::TONE_BAD, place: nil, detail: nil, target_id: nil)
      Item.new(key:, kind:, tone:, title:, subject:, place: place || all_workspaces, detail:, at:, target:, target_id:)
    end

    def all_workspaces = "All workspaces"

    def workflow_items
      failed = WorkflowRuns.failed_in(@filter.since, workspace: @filter.workspace, limit: PER_KIND).map do |workflow|
        step = workflow.steps.find(&:failed?)
        item(key: "workflow-#{workflow.id}", kind: KIND_WORKFLOW_FAILED, title: "Workflow step failed",
             subject: [ workflow.workflow_class, step&.name ].compact.join(" · "), place: subject_place(workflow.subject),
             detail: step && "#{step.attempts} of #{step.max_attempts} attempts used · #{step.last_error.to_s.lines.first&.strip}",
             at: workflow.updated_at, target: TARGET_WORKFLOW, target_id: workflow.id)
      end
      stuck = WorkflowRuns.stuck(workspace: @filter.workspace, limit: PER_KIND).map do |workflow|
        item(key: "stuck-#{workflow.id}", kind: KIND_WORKFLOW_STUCK, tone: IncidentProcess::TONE_WARN, title: "Workflow not moving",
             subject: workflow.workflow_class, place: subject_place(workflow.subject), detail: "#{workflow.state}, nothing recorded since",
             at: workflow.updated_at, target: TARGET_WORKFLOW, target_id: workflow.id)
      end
      failed + stuck
    end

    def webhook_items
      deliveries = WebhookDelivery.failed.where(updated_at: @filter.range).joins(:webhook)
      deliveries = @filter.scope(deliveries, "webhooks.workspace_id")
      deliveries.includes(:incident_event, webhook: :workspace).order(updated_at: :desc).group_by(&:webhook).first(PER_KIND).map do |webhook, failures|
        latest = failures.first
        item(key: "webhook-#{webhook.id}", kind: KIND_WEBHOOK_FAILING, title: "Webhook delivery failing",
             subject: "#{latest.event_type} to #{host_of(webhook.url)}", place: webhook.workspace.name,
             detail: [ "#{failures.size} failed", ("HTTP #{latest.response_code}" if latest.response_code) ].compact.join(" · "),
             at: latest.updated_at, target: TARGET_INCIDENT, target_id: latest.incident_event.incident_id)
      end
    end

    def platform_items
      failures = @filter.scope(PlatformCallFailure.where(created_at: @filter.range)).includes(:workspace).order(created_at: :desc)
      groups = failures.group_by { |failure| [ failure.workspace_id, failure.operation, failure.error_class, failure.channel_id ] }.first(PER_KIND)
      incidents = incidents_by_channel(groups.map(&:last).map(&:first))

      groups.map do |(_workspace_id, operation, error_class, channel_id), group|
        latest = group.first
        incident = incidents[[ latest.workspace_id, channel_id ]]
        item(key: "platform-#{latest.id}", kind: KIND_PLATFORM_FAILED, title: "#{latest.platform.titleize} call failed",
             subject: [ operation, incident&.identifier ].compact.join(" · "), place: latest.workspace.name,
             detail: "#{group.size} #{'time'.pluralize(group.size)} · #{error_class}", at: latest.created_at,
             target: (TARGET_INCIDENT if incident), target_id: incident&.id)
      end
    end

    def alert_items
      stuck = Alert.pending_routing.where(received_at: ...ALERT_STUCK_AFTER.ago)
                   .or(Alert.where(routing_state: Alert::ROUTING_FAILED, updated_at: @filter.range))
      @filter.scope(stuck).includes(:workspace, :alert_source).order(received_at: :desc).limit(PER_KIND).map do |alert|
        item(key: "alert-#{alert.id}", kind: KIND_ALERT_STUCK, tone: IncidentProcess::TONE_WARN, title: "Alert stuck in routing",
             subject: alert.title, place: alert.workspace.name,
             detail: "#{alert.alert_source.name} · routing #{alert.routing_state} · #{alert.routing_attempts} #{'attempt'.pluralize(alert.routing_attempts)}",
             at: alert.received_at, target: (TARGET_INCIDENT if alert.incident_id), target_id: alert.incident_id)
      end
    end

    # The job queue is shared by all workspaces, so queue items show only when no workspace is selected.
    def job_items
      return [] if @jobs.nil? || @filter.workspace

      backed_up = @jobs.backed_up.map do |queue|
        item(key: "queue-#{queue.name}", kind: KIND_QUEUE_BACKED_UP, tone: IncidentProcess::TONE_WARN, title: "Queue backing up",
             subject: queue.name, detail: "#{queue.waiting} waiting · oldest since #{queue.oldest_at.utc.iso8601}",
             at: queue.oldest_at, target: TARGET_QUEUES)
      end
      failed = @jobs.failed_kinds.first(PER_KIND).map do |kind|
        item(key: "jobs-#{kind.job_class}", kind: KIND_JOBS_FAILED, title: "Jobs failed", subject: kind.job_class,
             detail: "#{kind.count} failed and held", at: kind.last_at, target: TARGET_FAILED_JOBS)
      end
      backed_up + failed
    end

    def halon_items
      runs = HalonRuns.in(@filter).includes(:workspace, :subject)
      failed = HalonRuns.ending_scope(runs, HalonRuns::ENDING_FAILED).order(completed_at: :desc).limit(PER_KIND).map do |run|
        halon_item(run, KIND_HALON_FAILED, "Halon failed on our side", run.error_summary || "No cause recorded", IncidentProcess::TONE_BAD)
      end
      limits = runs.where(status: Investigation::STATUS_FAILED, error_summary: TUNING_LIMITS).order(completed_at: :desc).limit(PER_KIND).map do |run|
        halon_item(run, KIND_HALON_LIMIT, "Halon #{run.error_summary.downcase_first}", "#{run.turns_used} turns · #{Money.dollars(run.spent_micros)} of #{Money.dollars(run.max_spend_cents * 10_000)}", IncidentProcess::TONE_WARN)
      end
      not_posted = runs.where.not(completed_at: nil).where.not(thread_id: nil).where(answer_posted_at: nil).order(completed_at: :desc).limit(PER_KIND).map do |run|
        halon_item(run, KIND_HALON_NOT_POSTED, "Halon's last post did not reach the thread", "#{HalonRuns.ending(run.status, run.error_summary)}, saved but not posted", IncidentProcess::TONE_BAD)
      end
      stuck = @filter.scope(Investigation.abandoned).includes(:workspace, :subject).limit(PER_KIND).map do |run|
        halon_item(run, KIND_HALON_STUCK, "Halon run has no worker", "#{run.status} · attempt #{run.attempts} of #{Investigation::MAX_ATTEMPTS}", IncidentProcess::TONE_WARN, at: run.lease_until || run.created_at)
      end
      failed + limits + not_posted + stuck
    end

    def halon_item(run, kind, title, detail, tone, at: nil)
      item(key: "#{kind}-#{run.id}", kind: kind, tone: tone, title: title, subject: run_label(run), place: run.workspace.name,
           detail: detail, at: at || run.completed_at || run.created_at, target: TARGET_RUN, target_id: run.id)
    end

    def run_label(run)
      run.incident ? "#{run.incident.identifier} #{run.incident.name}" : run.question.to_s
    end

    def subject_place(subject)
      subject.respond_to?(:workspace) ? subject.workspace.name : all_workspaces
    end

    def incidents_by_channel(failures)
      pairs = failures.filter_map { |failure| [ failure.workspace_id, failure.channel_id ] if failure.channel_id }
      return {} if pairs.empty?

      Incident.where(workspace_id: pairs.map(&:first), channel_id: pairs.map(&:last)).index_by { |incident| [ incident.workspace_id, incident.channel_id ] }
    end

    def host_of(url)
      URI(url.to_s).host || url.to_s
    rescue URI::InvalidURIError
      url.to_s
    end
  end
end
