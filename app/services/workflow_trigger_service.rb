# Starts a run of every workflow something that happened matches (Workflow::Listening), each as its own identity with
# what happened as its trigger data. Every start goes through WorkflowRunService, so the workflows flag, a workflow's
# most runs an hour and one live run per subject all apply. One event starts a workflow once however often it is heard,
# since its key is the run's start key. A start past the hour's limit is counted as skipped on the workflow, any other
# start the limits refuse is kept on it for its page, as a scheduled start's is, and neither stops the workflows after
# it.
class WorkflowTriggerService
  def initialize(workspace)
    @workspace = workspace
  end

  # Answers the runs it started.
  def heard!(kind, key:, subject:, details: {}, actor: nil)
    return [] unless FeatureFlags.enabled?(@workspace, FeatureFlags::WORKFLOWS)

    listening = Workflow.listening(@workspace, kind).includes(:live_version).to_a
    return [] if listening.empty?

    built = Workflow::TriggerPayloads.new(@workspace).build(kind, subject, details.to_h)
    event = Workflow::Trigger::Events::Event.new(kind: kind, key: key, payload: built.payload, context: built.context, tags: built.tags, actor: actor)
    listening.select { |workflow| workflow.hears?(event) }.filter_map { |workflow| start(workflow, event) }
  end

  # A signed POST to one workflow's own address. Answers the run it started, nil when what it was sent does not meet
  # the trigger's conditions, or raises Workflow::Run::Refused with why not, which the caller hands back to whoever sent
  # it. A delivery sent again under the same id answers the run it started the first time.
  def hooked!(workflow, body:, delivery: nil, now: Time.current)
    raise Workflow::Run::Refused, workflow.start_blocked_reason || "#{workflow.name} does not start on its webhook." unless workflow.hooked?

    key = delivery.presence || Digest::SHA256.hexdigest(body.to_json)
    details = { "body" => body, "received_at" => now.utc.iso8601, "delivery" => delivery.presence }
    built = Workflow::TriggerPayloads.new(@workspace).build(Workflow::Trigger::KIND_INBOUND_WEBHOOK, workflow, details)
    event = Workflow::Trigger::Events::Event.new(kind: Workflow::Trigger::KIND_INBOUND_WEBHOOK, key: key, payload: built.payload, context: built.context)
    return nil unless workflow.hears?(event)

    run = WorkflowRunService.new(workflow).start!(
      started_by_kind: Workflow::Run::STARTED_BY_TRIGGER, trigger_kind: event.kind, trigger_payload: event.payload, start_key: event.start_key
    )
    workflow.trigger_started!
    run
  rescue Workflow::Run::Refused => refused
    workflow.trigger_start_refused!(refused)
    raise
  end

  private

  def start(workflow, event)
    run = WorkflowRunService.new(workflow).start!(
      started_by_kind: Workflow::Run::STARTED_BY_TRIGGER, trigger_kind: event.kind, trigger_payload: event.payload, start_key: event.start_key
    )
    workflow.trigger_started!
    run
  rescue Workflow::Run::Refused => refused
    workflow.trigger_start_refused!(refused)
    nil
  rescue StandardError => error
    Rails.logger.error({ event: "workflow_trigger.start_failed", workflow_id: workflow.id, kind: event.kind, error: error.class.name, message: error.message }.to_json)
    nil
  end
end
