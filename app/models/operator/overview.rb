module Operator
  # Summary numbers for each area on the overview, for one window. jobs is nil when the queue cannot be read.
  class Overview
    Incidents = Data.define(:declared, :from_alerts, :platform_failures, :webhooks_failed, :webhooks_sent, :alerts_waiting, :oldest_alert_at)
    Workflows = Data.define(:ran, :failed, :retrying, :paused, :kinds)
    Jobs = Data.define(:finished, :failed, :waiting, :oldest_waiting_at, :workers, :workers_alive)
    Halon = Data.define(:runs, :chat_turns, :answered, :finished, :stopped, :failed, :spent_micros)

    def initialize(filter, jobs:)
      @filter = filter
      @jobs = jobs
    end

    def incidents
      declared = @filter.scope(Incident.where(declared_at: @filter.range))
      deliveries = @filter.scope(WebhookDelivery.joins(:webhook).where(created_at: @filter.range), "webhooks.workspace_id")
      waiting = @filter.scope(Alert.pending_routing)
      Incidents.new(
        declared: declared.count, from_alerts: declared.where(id: Alert.select(:incident_id)).count,
        platform_failures: @filter.scope(PlatformCallFailure.where(created_at: @filter.range)).count,
        webhooks_failed: deliveries.failed.count, webhooks_sent: deliveries.count,
        alerts_waiting: waiting.count, oldest_alert_at: waiting.minimum(:received_at)
      )
    end

    def workflows
      counts = WorkflowRuns.window_counts(@filter.since, workspace: @filter.workspace)
      started = WorkflowRuns.started(@filter.since, workspace: @filter.workspace)
      Workflows.new(
        ran: counts.values.sum, failed: counts.fetch(WorkflowRuns::STATE_FAILED, 0), paused: counts.fetch(WorkflowRuns::STATE_PAUSED, 0),
        retrying: WorkflowRuns.retrying_count(@filter.since, workspace: @filter.workspace),
        kinds: started.distinct.count(:workflow_class)
      )
    end

    def jobs
      return nil unless @jobs

      Jobs.new(finished: @jobs.finished, failed: @jobs.failed, waiting: @jobs.waiting, oldest_waiting_at: @jobs.oldest_waiting_at,
               workers: @jobs.workers, workers_alive: @jobs.workers_alive)
    end

    def halon
      totals = HalonHealth.new(@filter).totals
      endings = HalonRuns.in(@filter).pluck(:status, :error_summary).map { |status, summary| HalonRuns.ending(status, summary) }.tally
      Halon.new(
        runs: totals.runs, chat_turns: totals.chat_turns, answered: totals.answered, finished: totals.finished,
        stopped: endings.fetch(HalonRuns::ENDING_STOPPED, 0), failed: endings.fetch(HalonRuns::ENDING_FAILED, 0),
        spent_micros: totals.spent_micros
      )
    end
  end
end
