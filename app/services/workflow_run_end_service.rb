# What happens once a run ends. A watch its steps still keep stops, since nothing waits for it any more, and a question
# or an approval its steps still ask is withdrawn where it was asked. A run that
# failed on its own is said in the channel of the team that owns the workflow, from the catalog, else to whoever
# published it by direct message, with Halon's suggested fix waiting on the run's page when it has one. A workflow that
# asks for an all clear says so in one line when a run found nothing to raise or post. A test run and a run another
# workflow started say nothing, since someone is looking at them. Each run is told once.
class WorkflowRunEndService
  # A place that will not take the notice however often it is tried, so the next place is tried instead.
  UNREACHABLE = [ AdapterError::NotFound, AdapterError::NotInChannel, AdapterError::IsArchived ].freeze

  # job_id names the job telling it, so a job its stopped worker left takes its own claim back when it runs again.
  def initialize(run, job_id: SecureRandom.uuid)
    @run = run
    @workflow = run.workflow
    @workspace = run.workspace
    @job_id = job_id
  end

  def ended!
    stop_watches!
    withdraw_asks!
    close_sandbox!
    Conversation::Workflows.moved!(@workflow) unless @run.test?
    tell_workflows!
    return if @run.test? || @run.parent_run_id.present? || !@run.claim_telling!(@job_id)

    tell!
  end

  private

  # Whatever breaks once this job holds the claim gives it back, so the run is never left held by a job that stopped.
  def tell!
    if @run.failed?
      tell_failed!
    else
      tell_all_clear!
      @run.told!
    end
  rescue StandardError
    @run.release_telling!(@job_id)
    raise
  end

  # Other workflows hear that a real run failed, once per run. A run another workflow ran is heard through the run that
  # ran it, which fails with it, and a workflow never hears its own run fail.
  def tell_workflows!
    return unless @run.failed? && !@run.test? && @run.parent_run_id.nil?

    Workflow::Trigger::Events.fire!(@workspace, Workflow::Trigger::KIND_RUN_FAILED, key: @run.id, subject: @run, actor: @run.agent)
  end

  def withdraw_asks!
    Workflow::Run::Question.open.where(run_step_id: @run.steps.select(:id)).find_each { |question| WorkflowQuestionService.withdraw!(question) }
    @workspace.ability_approvals.pending.where(workflow_run_id: @run.id, action_key: Ability::Action::WORKFLOW_APPROVAL).find_each do |approval|
      ApprovalNotificationService.mark_resolved!(approval) if approval.expire!(reason: "The run #{ended_words} before anyone decided.").expired?
    end
  end

  def ended_words
    return "was stopped" if @run.status == Workflow::Run::STATUS_CANCELLED
    return "failed" if @run.failed?

    "ended"
  end

  # The run's sandbox, which its steps' commands, scripts and browser ran in, stops with it rather than at the next
  # sweep for idle boxes.
  def close_sandbox!
    Integrations::CodeReading.close(@run.code_box_key)
  rescue Integrations::Error => error
    Rails.logger.warn({ event: "workflow_run.sandbox_not_closed", run_id: @run.id, error: error.message }.to_json)
  end

  def stop_watches!
    Chat::Watch.active.joins(:chat).where(chats: { owner_type: Workflow::Run::Step.name, owner_id: @run.steps.select(:id) }).find_each do |watch|
      Conversation::Watches.finish!(watch, Chat::Watch::STATUS_STOPPED, "Stopped, since the run it was for ended.")
    end
  end

  # Counted as told only once it lands. The team's channel first, and whoever published the workflow, by direct message,
  # when the workflow has no team or its channel cannot be posted in. A platform error gives the claim back and raises,
  # so WorkflowRunEndedJob tries again later, with the fix Halon already suggested rather than a new one.
  def tell_failed!
    suggested = @workflow.edits.exists?(source_run_id: @run.id) || suggest_repair!
    return @run.told! if [ where_to_tell, publisher ].compact.uniq.any? { |place| told_failure?(place, suggested) }

    Rails.logger.warn({ event: "workflow_run.failure_untold", run_id: @run.id, reason: "nowhere_to_tell" }.to_json)
    @run.release_telling!(@job_id)
  end

  def told_failure?(place, suggested)
    adapter.post_workflow_failure(channel_id: place, run: @run, suggestion: suggested)
    true
  rescue *UNREACHABLE => error
    Rails.logger.warn({ event: "workflow_run.failure_place_unreachable", run_id: @run.id, error: error.class.name }.to_json)
    false
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
  def where_to_tell = @workflow.team_channel_id || publisher

  def publisher
    @run.version.published_by&.platform_user_id.presence || @workflow.live_version&.published_by&.platform_user_id.presence
  end

  # Halon reads why the step failed and, when its settings caused it, suggests a change as a proposal on the workflow,
  # which a person accepts or dismisses. True when it made one. Once per kind of failure for each published version
  # (Workflow::Version#claim_repair!), so a run failing in a way Halon already looked at spends nothing, unless that look
  # broke before Halon answered.
  def suggest_repair!
    return false if Investigation.unavailable_reason(@workspace)

    failed = @run.steps.find_by(status: Workflow::Run::Step::STATUS_FAILED)
    spec = failed && @run.version.steps_by_id[failed.step_key]
    return false unless spec && DefinedWorkflow::Steps.for(spec["kind"]) && !DefinedWorkflow::Steps.for(spec["kind"]).engine?
    return false unless @run.version.claim_repair!(failed.step_key, failed.error.presence || @run.error)

    suggestion = FirefightAi::WorkflowRepair.new(@workspace, inferable: @run).suggest(
      workflow_name: @workflow.name, step: spec.slice("name", "kind", "config"), error: failed.error.presence || @run.error,
      kind_words: DefinedWorkflow::Steps.for(spec["kind"]).label
    )
    return false unless suggestion

    @workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_CONFIG, payload: { step_id: spec["id"], changes: { config: suggestion.config } },
                    by: nil, halon: true, reason: suggestion.reason, source_run: @run)
    true
  rescue FirefightAi::TransientError, FirefightAi::TerminalError, FirefightAi::Canceled => error
    @run.version.release_repair!(failed.step_key, failed.error.presence || @run.error)
    unsuggested(error)
  rescue Workflow::Edit::Refused => error
    unsuggested(error)
  end

  def unsuggested(error)
    Rails.logger.warn({ event: "workflow_run.repair_unsuggested", run_id: @run.id, error: error.class.name }.to_json)
    false
  end

  def adapter = @adapter ||= WorkspaceAdapter.for(@workspace)
end
