# Applies a run's fix as the person who applied it, or as Halon for a fix it applied under an unattended rule
# (Investigation::Unattended). Each step that runs a tool goes through the gateway as them, in the
# order the fix gives, once the steps it waits on are done. A step an approval rule holds waits for its approver, and once
# approved for someone to run it, after Halon reads how things stand now. Approving a step never runs it.
# A step that fails, or is declined, stops the steps that wait on it, and the rest stand. The run's thread carries one
# message that follows along, and the run page reads the same rows.
class Investigation::FixRunner
  # How often a coding agent's steps are kept on the fix step at most while it works. The run page reads them from there.
  PROGRESS_SAVED_EVERY = 2

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

  # A step of a cancelled fix that had not run never will, and an approval it waited on, or that waited for it, is withdrawn.
  def self.stop(step)
    was = step.status
    who = step.plan.cancelled_by&.display_name || "someone"
    stopped = step.move!(from: [ Investigation::RemediationStep::STATUS_PROPOSED, Investigation::RemediationStep::STATUS_WAITING_APPROVAL,
                                 Investigation::RemediationStep::STATUS_APPROVED ],
                         to: Investigation::RemediationStep::STATUS_SKIPPED, result: "Cancelled by #{who} before it ran.")
    return unless stopped

    withdraw(step.approval) if was == Investigation::RemediationStep::STATUS_WAITING_APPROVAL
    step.approval&.dismiss! if was == Investigation::RemediationStep::STATUS_APPROVED
  end

  def self.withdraw(approval)
    return unless approval&.pending?

    approval.expire!
    ApprovalNotificationService.mark_resolved!(approval)
  end
  private_class_method :withdraw

  # From ApprovalResumption, once the approver of a step held by a rule decided. A denial ends the step. An approval
  # leaves it for someone to run, once Halon has read how things stand now, and tells whoever applied the fix.
  def self.resume!(approval, step_id)
    step = Investigation::RemediationStep.find_by(id: step_id, approval_id: approval.id)
    return unless step
    return InvestigationFixJob.perform_later(step.plan_id, step.id, approval.id) unless approval.approved?
    return unless step.move!(from: Investigation::RemediationStep::STATUS_WAITING_APPROVAL, to: Investigation::RemediationStep::STATUS_APPROVED)

    ApprovedCallExpiryJob.set(wait_until: approval.run_expires_at).perform_later(approval.id) if approval.run_expires_at
    FixStepCheckJob.perform_later(step.id)
    new(step.plan).told!(step)
  end

  # Halon reads how things stand now, as whoever applied the fix and only through reads.
  def self.check!(step)
    return unless step.checking?

    report = Chat::StateCheck.run(
      owner: step, workspace: step.plan.finding.investigation.workspace, principal: step.plan.acting_principal,
      source: AbilityGateway::SOURCE_INVESTIGATION,
      call: Chat::StateCheck::Call.new(named: "Step #{step.position} of a fix: #{step.description} (#{step.tool_name})",
                                       asked: Chat::Tools.shown_arguments(step.arguments), approved_by: approver_name(step.approval))
    )
    new(step.plan).publish! if step.checked!(report)
  end

  # Someone pressed Run on an approved step. It runs once, as whoever applied the fix, with its approval. Returns why not,
  # or nil.
  def self.run_approved!(step, by:)
    blocked = step.run_blocked_reason(by)
    return blocked if blocked
    return step.reload.run_blocked_reason(by) || "Step #{step.position} is no longer waiting to be run." unless
      step.claim!(from: Investigation::RemediationStep::STATUS_APPROVED, started_at: Time.current, done_by_id: by.id)

    InvestigationFixJob.set(wait: step.stale_after + 1.minute).perform_later(step.plan_id)
    InvestigationFixJob.perform_later(step.plan_id, step.id, step.approval_id)
    nil
  end

  # Someone chose not to run an approved step. It is skipped like a step that did not go through, so what waits on it
  # never runs, and its approval can no longer be used.
  def self.dismiss_approved!(step, by:)
    blocked = step.dismiss_blocked_reason(by)
    return blocked if blocked
    dismissed = step.move!(from: Investigation::RemediationStep::STATUS_APPROVED, to: Investigation::RemediationStep::STATUS_SKIPPED,
                           result: "Dismissed by #{by.display_name} after it was approved. It did not run.", finished_at: Time.current)
    return "Step #{step.position} is no longer waiting to be run." unless dismissed

    step.approval&.dismiss!
    InvestigationFixJob.perform_later(step.plan_id)
    nil
  end

  # An approval that expired is asked for again, for exactly the same call. Nothing runs.
  def self.ask_again!(step, by:)
    blocked = step.ask_again_blocked_reason(by)
    return blocked if blocked

    approval = step.request_approval_again!
    return "No approval rule holds this step any more. Cancel the fix and apply it again to run it." unless approval

    ApprovalResumption.park_fix_step!(approval, step)
    new(step.plan).publish!
    nil
  rescue AbilityGateway::Denied
    "#{step.plan.applier_name || 'Whoever applied the fix'} may no longer run #{step.tool_name}, so it cannot be asked for again."
  end

  # Nobody ran an approved step within its window. It stays, saying so, until someone asks again, dismisses it or cancels.
  def self.lapsed!(approval, step_id)
    step = Investigation::RemediationStep.find_by(id: step_id, approval_id: approval.id)
    new(step.plan).told!(step) if step&.approved?
  end

  def self.approver_name(approval) = approval&.approver&.actor_display_name || "An approver"

  def initialize(plan)
    @plan = plan
  end

  # Runs whatever is ready, then settles the fix and redraws the thread. A held step resumes first, with its approval.
  # interrupted_at is when an earlier run of the same job started, when that run was cut off part way.
  def advance!(step_id: nil, approval_id: nil, interrupted_at: nil)
    give_up_on_interrupted!(interrupted_at, step_id) if interrupted_at
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

  # A step the cut off run had started may or may not have gone through, so it ends saying to check, at once rather than
  # once it goes stale, and is never run again. One job runs a fix at a time, so the cut off run's steps are the one it
  # was handed and any it claimed itself after it started. A step someone pressed Run on carries its approval and waits
  # for its own job.
  def give_up_on_interrupted!(interrupted_at, step_id)
    @plan.steps.reload.select do |step|
      step.status == Investigation::RemediationStep::STATUS_RUNNING &&
        (step.id == step_id || (step.approval_id.nil? && step.started_at.present? && step.started_at >= interrupted_at))
    end.each { |step| step.finish!(Investigation::RemediationStep::STATUS_FAILED, result: LOST_TRACK) }
  end

  def hold_back!
    @plan.steps.reload.each do |step|
      step.move!(from: Investigation::RemediationStep::STATUS_PROPOSED, to: Investigation::RemediationStep::STATUS_SKIPPED) if step.proposed? && step.held_back?(@plan.steps)
    end
  end

  # A denial ends the step and tells whoever applied the fix. A step someone pressed Run on was claimed already, and runs
  # here once, while its approval is still unused.
  def resume(step, approval_id)
    approval = workspace.ability_approvals.find_by(id: approval_id)
    if approval&.denied?
      told!(step) if step.finish!(Investigation::RemediationStep::STATUS_DECLINED,
                                  result: "#{approval.approver&.actor_display_name || 'The approver'} declined it.")
    elsif step.status == Investigation::RemediationStep::STATUS_RUNNING && approval&.usable?
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
    return step.finish!(Investigation::RemediationStep::STATUS_FAILED, result: APPLIER_GONE) unless @plan.acting_principal

    tool = step.tool_to_run(workspace)
    return step.finish!(Investigation::RemediationStep::STATUS_FAILED, result: "#{step.tool_name || 'The coding tool'} is no longer switched on.") unless tool

    integration = tool.integration
    environment_entry = step.environment_entry(tool)
    arguments = step.call_arguments
    authorization = step.authorize_call!(tool, scope: step.call_scope(tool), arguments: arguments, approval_id: approval_id)
    finish_call(step, authorization) do
      integration.executor.call(tool: tool, environment_row: integration.resolve_environment(environment_entry&.id), arguments: arguments,
                                box_key: @plan.finding.investigation.code_box_key, progress: progress_of(step),
                                request: (step.code_agent_request(@plan.approved_by) if step.pull_request?))
    end
  rescue Integration::UnknownEnvironment => error
    step.finish!(Investigation::RemediationStep::STATUS_FAILED, result: error.message)
  rescue AbilityGateway::Denied
    step.finish!(Investigation::RemediationStep::STATUS_FAILED,
                 result: "#{@plan.applier_name} may not run #{step.tool_name} here, or its connection is not set up for this environment.")
  rescue AbilityGateway::PendingApproval => pending
    step.move!(from: Investigation::RemediationStep::STATUS_RUNNING, to: Investigation::RemediationStep::STATUS_WAITING_APPROVAL, approval_id: pending.approval.id)
    ApprovalResumption.park_fix_step!(pending.approval, step)
    # Cancelled while this step was asking, so nobody is left asked to approve a fix that stopped.
    self.class.stop(step) if @plan.reload.cancelled?
  rescue StandardError => error
    Rails.logger.warn({ event: "fix.step_not_started", step_id: step.id, error: error.class.name }.to_json)
    step.finish!(Investigation::RemediationStep::STATUS_FAILED, result: COULD_NOT_FINISH)
  end

  # A tool that runs long, such as a coding agent writing a change, says how it is going. The step shows it and the
  # thread is redrawn, and a report that cannot be kept never stops the step. A connected coding agent says it in a
  # sentence. Firefight's own reports each thing it did (Chat::CodeFixProgress), several a second at times, so the step keeps
  # it every few seconds and the thread is redrawn no more often than the platform allows.
  def progress_of(step)
    saving = Chat::CodeFixProgress::Pace.new(every: PROGRESS_SAVED_EVERY)
    redrawing = nil
    lambda do |update|
      if update.is_a?(Chat::CodeFixProgress)
        next unless saving.due?(step.id, update) && step.track!(update)

        redrawing ||= Chat::CodeFixProgress::Pace.new(every: WorkspaceAdapter.for(workspace).agent_step_update_interval)
        publish! if redrawing.due?(step.id, update)
      elsif step.progress!(update)
        publish!
      end
    rescue StandardError => error
      Rails.logger.warn({ event: "fix.progress_not_kept", step_id: step.id, error: error.class.name }.to_json)
    end
  end

  # The tool's own words are the result, failure or not. The ledger row says whether the call went through.
  def finish_call(step, authorization)
    result = yield
    text = Array(result["content"]).filter_map { |part| part["text"] if part.is_a?(Hash) }.join("\n").strip
    if result["isError"] == true
      authorization.answer_failed!(text)
      authorization.finalize_answered!
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

  public

  # One message in the run's thread, posted when the fix is applied and redrawn after, and the answer redrawn once
  # without its Apply fix. A fix nobody applied has no message, its steps are marked done on the run page.
  def publish!
    @plan.reload
    investigation = @plan.finding.investigation
    return if investigation.thread_id.blank? || (@plan.approved_by_id.nil? && !@plan.unattended?)

    adapter = WorkspaceAdapter.for(workspace)
    if @plan.progress_message_id
      adapter.update_fix_progress(channel_id: @plan.progress_channel_id, message_id: @plan.progress_message_id, plan: @plan)
    else
      posted = adapter.post_fix_progress(channel_id: investigation.channel_id, thread_id: investigation.thread_id, plan: @plan)
      return redraw_answer(adapter, investigation) if @plan.claim_progress_message!(channel_id: posted[:channel_id], message_id: posted[:message_id])

      # Another worker posted first, so this message goes and the one the thread keeps is brought up to date.
      adapter.delete_message(channel_id: posted[:channel_id], message_id: posted[:message_id])
      adapter.update_fix_progress(channel_id: @plan.progress_channel_id, message_id: @plan.progress_message_id, plan: @plan)
    end
  rescue AdapterError => error
    Rails.logger.warn({ event: "fix.progress_not_posted", plan_id: @plan.id, error: error.class.name }.to_json)
  end

  # The thread follows the fix when it has one. A fix applied where there is no thread tells whoever applied it directly,
  # since nobody is watching the run page.
  def told!(step)
    publish!
    applier = @plan.reload.approved_by
    return if @plan.finding.investigation.thread_id.present? || applier&.platform_user_id.blank?

    WorkspaceAdapter.for(workspace).post_fix_step_to_user(user_id: applier.platform_user_id, step: step.reload)
  rescue AdapterError => error
    Rails.logger.warn({ event: "fix.step_untold", step_id: step.id, error: error.class.name }.to_json)
  end

  private

  def redraw_answer(adapter, investigation)
    return if investigation.answer_message_id.blank?

    adapter.update_investigation_answer(channel_id: investigation.channel_id, message_id: investigation.answer_message_id, finding: @plan.finding)
  end
end
