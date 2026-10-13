# What happens once a run ends. A watch its steps still keep stops, since nothing waits for it any more. A run that
# failed on its own is said in the channel of the team that owns the workflow, from the catalog, else to whoever
# published it by direct message, with Halon's suggested fix waiting on the run's page when it has one. A workflow that
# asks for an all clear says so in one line when a run found nothing to raise or post. A test run and a run another
# workflow started say nothing, since someone is looking at them. Each run is told once.
class WorkflowRunEndService
  def initialize(run)
    @run = run
    @workflow = run.workflow
    @workspace = run.workspace
  end

  def ended!
    stop_watches!
    return if @run.test? || @run.parent_run_id.present? || !@run.claim_telling!

    @run.failed? ? tell_failed! : tell_all_clear!
  end

  private

  def stop_watches!
    Chat::Watch.active.joins(:chat).where(chats: { owner_type: Workflow::Run::Step.name, owner_id: @run.steps.select(:id) }).find_each do |watch|
      Conversation::Watches.finish!(watch, Chat::Watch::STATUS_STOPPED, "Stopped, since the run it was for ended.")
    end
  end

  def tell_failed!
    suggested = suggest_repair!
    place = where_to_tell
    return unless place

    adapter.post_workflow_failure(channel_id: place, run: @run, suggestion: suggested)
  rescue AdapterError => error
    Rails.logger.warn({ event: "workflow_run.failure_untold", run_id: @run.id, error: error.class.name }.to_json)
  end

  def tell_all_clear!
    return unless @run.succeeded? && @workflow.all_clear?
    return if @run.notices.exists? || @run.steps.where(kind: DefinedWorkflow::Steps::PostToChannel.kind, status: Workflow::Run::Step::STATUS_SUCCEEDED).exists?

    place = where_to_tell
    adapter.post_workflow_all_clear(channel_id: place, run: @run) if place
  rescue AdapterError => error
    Rails.logger.warn({ event: "workflow_run.all_clear_untold", run_id: @run.id, error: error.class.name }.to_json)
  end

  # The owning team's channel, else whoever published it, by direct message.
  def where_to_tell
    team = @workflow.owner_team&.role_value(CatalogAttributeDefinition::ROLE_NOTIFICATION_CHANNEL).presence
    team || @run.version.published_by&.platform_user_id.presence || @workflow.live_version&.published_by&.platform_user_id.presence
  end

  # Halon reads why the step failed and, when its settings caused it, suggests a change as a proposal on the workflow,
  # which a person accepts or dismisses. True when it made one.
  def suggest_repair!
    return false if Investigation.unavailable_reason(@workspace)

    failed = @run.steps.find_by(status: Workflow::Run::Step::STATUS_FAILED)
    spec = failed && @run.version.steps_by_id[failed.step_key]
    return false unless spec && DefinedWorkflow::Steps.for(spec["kind"]) && !DefinedWorkflow::Steps.for(spec["kind"]).engine?

    suggestion = FirefightAi::WorkflowRepair.new(@workspace, inferable: @run).suggest(
      workflow_name: @workflow.name, step: spec.slice("name", "kind", "config"), error: failed.error.presence || @run.error,
      kind_words: DefinedWorkflow::Steps.for(spec["kind"]).label
    )
    return false unless suggestion

    @workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_CONFIG, payload: { step_id: spec["id"], changes: { config: suggestion.config } },
                    by: nil, halon: true, reason: suggestion.reason, source_run: @run)
    true
  rescue FirefightAi::TransientError, FirefightAi::TerminalError, Workflow::Edit::Refused => error
    Rails.logger.warn({ event: "workflow_run.repair_unsuggested", run_id: @run.id, error: error.class.name }.to_json)
    false
  end

  def adapter = @adapter ||= WorkspaceAdapter.for(@workspace)
end
