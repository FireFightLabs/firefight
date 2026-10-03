# Applies a run's fix as the person who applied it. Each step that runs a tool goes through the gateway as them, in the
# order the fix gives, once the steps it waits on are done. A step an approval rule holds waits for its approver and
# carries on when approved. A step that fails, or is declined, stops the steps that wait on it, and the rest stand. The
# run's thread carries one message that follows along, and the run page reads the same rows.
class Investigation::FixRunner
  ALREADY_APPLIED = "Someone else applied this fix a moment ago.".freeze
  APPLYING = "Applying the fix. Each step shows how it went.".freeze
  MARKED_DONE = "Marked done.".freeze
  # A failure on our side, never the technical cause, which is logged.
  COULD_NOT_FINISH = "Firefight could not finish this step. Check whether it went through, then do it by hand if it did not.".freeze
  LOST_TRACK = "Firefight lost track of this step while it ran. Check whether it went through, then do it by hand if it did not.".freeze
  APPLIER_GONE = "Whoever applied the fix is no longer a member of this workspace, so it cannot run as them.".freeze

  # Claims the fix for this person and starts it. Returns why it could not, or nil.
  def self.apply!(plan, by:, from:)
    blocked = plan.apply_blocked_reason(by)
    return blocked if blocked
    return ALREADY_APPLIED unless plan.apply!(by: by, from: from)

    InvestigationFixJob.perform_later(plan.id)
    nil
  end

  # A person did a step Firefight does not run. What waited on it goes, and the thread follows. Returns why not, or nil.
  def self.mark_done!(step, by:)
    blocked = step.mark_done_blocked_reason
    return blocked if blocked
    return step.reload.mark_done_blocked_reason unless step.mark_done!(by: by)

    InvestigationFixJob.perform_later(step.plan_id)
    nil
  end

  CANCELLED = "Cancelled. A step already running finishes, and whatever went through can be undone.".freeze
  UNDO_CANCELLED = "Cancelled. A step already running finishes.".freeze

  def self.cancelled_message(plan) = plan.undo? ? UNDO_CANCELLED : CANCELLED

  # Stops the steps that have not run, and withdraws the approvals they wait on, so nothing more runs. Returns why it
  # could not, or nil.
  def self.cancel!(plan, by:)
    blocked = plan.cancel_blocked_reason
    return blocked if blocked
    return plan.reload.cancel_blocked_reason || "This #{plan.undo? ? 'undo' : 'fix'} is no longer being applied." unless plan.cancel!(by: by)

    plan.steps.each { |step| stop(step) }
    InvestigationFixJob.perform_later(plan.id)
    nil
  end

  # A step of a cancelled fix that had not run never will, and an approval it waited on is withdrawn.
  def self.stop(step)
    waiting = step.status == Investigation::RemediationStep::STATUS_WAITING_APPROVAL
    who = step.plan.cancelled_by&.display_name || "someone"
    stopped = step.move!(from: [ Investigation::RemediationStep::STATUS_PROPOSED, Investigation::RemediationStep::STATUS_WAITING_APPROVAL ],
                         to: Investigation::RemediationStep::STATUS_SKIPPED, result: "Cancelled by #{who} before it ran.")
    withdraw(step.approval) if stopped && waiting
  end

  def self.withdraw(approval)
    return unless approval&.pending?

    approval.expire!
    ApprovalNotificationService.mark_resolved!(approval)
  end
  private_class_method :withdraw

  # From ApprovalResumption, once the approver of a step held by a rule decided.
  def self.resume!(approval, step_id)
    step = Investigation::RemediationStep.find_by(id: step_id, approval_id: approval.id)
    return unless step

    InvestigationFixJob.perform_later(step.plan_id, step.id, approval.id)
  end

  def initialize(plan)
    @plan = plan
  end

  # Runs whatever is ready, then settles the fix and redraws the thread. A held step resumes first, with its approval.
  def advance!(step_id: nil, approval_id: nil)
    give_up_on_stale!
    resume(@plan.steps.find(step_id), approval_id) if step_id
    if @plan.reload.applying?
      loop do
        hold_back!
        ready = @plan.steps.reload.find { |step| step.proposed? && step.ready?(@plan.steps) && step.runs_itself?(workspace) }
        break unless ready

        run(ready)
        publish!
      end
    end
    hold_back!
    @plan.settle!
    publish!
  end

  private

  def workspace = @plan.finding.investigation.workspace

  # A step waiting on one that failed, was declined or was itself held back never runs.
  # A step left running by a worker that died is ended, saying so, rather than holding the fix forever.
  def give_up_on_stale!
    @plan.steps.reload.select(&:stale?).each { |step| step.finish!(Investigation::RemediationStep::STATUS_FAILED, result: LOST_TRACK) }
  end

  def hold_back!
    @plan.steps.reload.each do |step|
      step.move!(from: Investigation::RemediationStep::STATUS_PROPOSED, to: Investigation::RemediationStep::STATUS_SKIPPED) if step.proposed? && step.held_back?(@plan.steps)
    end
  end

  def resume(step, approval_id)
    approval = workspace.ability_approvals.find_by(id: approval_id)
    if approval&.denied?
      step.finish!(Investigation::RemediationStep::STATUS_DECLINED, result: "#{approval.approver&.actor_display_name || 'The approver'} declined it.")
    elsif step.claim!(from: Investigation::RemediationStep::STATUS_WAITING_APPROVAL)
      call(step, approval_id: approval_id)
    elsif @plan.reload.cancelled?
      self.class.stop(step)
    end
  end

  # Claims the step, and books a look after it would have gone stale, so a worker dying mid-call never leaves it running.
  def run(step)
    return unless step.claim!(from: Investigation::RemediationStep::STATUS_PROPOSED, started_at: Time.current)

    InvestigationFixJob.set(wait: step.stale_after + 1.minute).perform_later(@plan.id)
    # A code change's arguments are fixed when it starts, so an approval asked for them still matches when it resumes.
    step.update_columns(arguments: step.code_arguments) if step.pull_request? && step.arguments.blank?
    call(step)
  end

  def call(step, approval_id: nil)
    return step.finish!(Investigation::RemediationStep::STATUS_FAILED, result: APPLIER_GONE) unless @plan.approved_by

    tool = step.tool_to_run(workspace)
    return step.finish!(Investigation::RemediationStep::STATUS_FAILED, result: "#{step.tool_name || 'The coding tool'} is no longer switched on.") unless tool

    integration = tool.integration
    asked = step.arguments
    environment_entry = integration.environment_entry_for(asked[Integration::Tool::ENVIRONMENT_ARG])
    arguments = asked.except(Integration::Tool::ENVIRONMENT_ARG)
    scope = environment_entry ? { "environment" => environment_entry.id } : {}
    authorization = step.authorize_call!(tool, scope: scope, arguments: arguments, approval_id: approval_id)
    finish_call(step, authorization) do
      integration.executor.call(tool: tool, environment_row: integration.resolve_environment(environment_entry&.id), arguments: arguments,
                                box_key: @plan.finding.investigation.code_box_key)
    end
  rescue Integration::UnknownEnvironment => error
    step.finish!(Investigation::RemediationStep::STATUS_FAILED, result: error.message)
  rescue AbilityGateway::Denied
    step.finish!(Investigation::RemediationStep::STATUS_FAILED,
                 result: "#{@plan.approved_by.display_name} may not run #{step.tool_name} here, or its connection is not set up for this environment.")
  rescue AbilityGateway::PendingApproval => pending
    step.move!(from: Investigation::RemediationStep::STATUS_RUNNING, to: Investigation::RemediationStep::STATUS_WAITING_APPROVAL, approval_id: pending.approval.id)
    ApprovalResumption.park_fix_step!(pending.approval, step)
    # Cancelled while this step was asking, so nobody is left asked to approve a fix that stopped.
    self.class.stop(step) if @plan.reload.cancelled?
  rescue StandardError => error
    Rails.logger.warn({ event: "fix.step_not_started", step_id: step.id, error: error.class.name }.to_json)
    step.finish!(Investigation::RemediationStep::STATUS_FAILED, result: COULD_NOT_FINISH)
  end

  # The tool's own words are the result, failure or not. The ledger row says whether the call went through.
  def finish_call(step, authorization)
    result = yield
    text = Array(result["content"]).filter_map { |part| part["text"] if part.is_a?(Hash) }.join("\n").strip
    if result["isError"] == true
      authorization.finalize_error!(Integrations::Error.new(text))
      step.finish!(Investigation::RemediationStep::STATUS_FAILED, result: text.presence || "#{step.tool_name} said it failed.", invocation_id: authorization.invocation_id)
    else
      authorization.finalize_success!
      step.finish!(Investigation::RemediationStep::STATUS_DONE, result: text.presence, invocation_id: authorization.invocation_id)
    end
  rescue Integrations::Error => error
    authorization.finalize_error!(error)
    step.finish!(Investigation::RemediationStep::STATUS_FAILED, result: error.message, invocation_id: authorization.invocation_id)
  rescue StandardError => error
    authorization.finalize_error!(error)
    Rails.logger.warn({ event: "fix.step_failed", step_id: step.id, error: error.class.name }.to_json)
    step.finish!(Investigation::RemediationStep::STATUS_FAILED, result: COULD_NOT_FINISH, invocation_id: authorization.invocation_id)
  end

  # One message in the run's thread, posted when the fix is applied and redrawn after, and the answer redrawn once
  # without its Apply fix. A fix nobody applied has no message, its steps are marked done on the run page.
  def publish!
    @plan.reload
    investigation = @plan.finding.investigation
    return if investigation.thread_id.blank? || @plan.approved_by_id.nil?

    adapter = WorkspaceAdapter.for(workspace)
    if @plan.progress_message_id
      adapter.update_fix_progress(channel_id: @plan.progress_channel_id, message_id: @plan.progress_message_id, plan: @plan)
    else
      posted = adapter.post_fix_progress(channel_id: investigation.channel_id, thread_id: investigation.thread_id, plan: @plan)
      @plan.claim_progress_message!(channel_id: posted[:channel_id], message_id: posted[:message_id])
      redraw_answer(adapter, investigation)
    end
  rescue AdapterError => error
    Rails.logger.warn({ event: "fix.progress_not_posted", plan_id: @plan.id, error: error.class.name }.to_json)
  end

  def redraw_answer(adapter, investigation)
    return if investigation.answer_message_id.blank?

    adapter.update_investigation_answer(channel_id: investigation.channel_id, message_id: investigation.answer_message_id, finding: @plan.finding)
  end
end
