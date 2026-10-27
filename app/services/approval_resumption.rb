# A person who clicked a button cannot re-issue a parked call the way API and
# MCP callers can, so the request is stored when it parks and replayed on approval.
class ApprovalResumption
  KIND_INTERACTION = "interaction"
  KIND_COMMAND = "command"
  KIND_WEB = "web"
  # A step of a run's fix, which carries on from where it was held, either way the approver decides.
  KIND_FIX_STEP = "fix_step"
  # A call to an issue tracker for an item's issue, run again as whoever asked once approved (IssueSyncService).
  KIND_ISSUE_SYNC = "issue_sync"
  # A call to an on-call tool for a page, run again as Firefight paging once approved (OnCallSyncService).
  KIND_PAGING = "paging"
  # A step of a workflow run, which waits parked and carries on from the decision, whichever way it goes.
  KIND_WORKFLOW_STEP = "workflow_step"
  # Publishing a workflow an agent made, which approving publishes at the revision it was asked about.
  KIND_WORKFLOW_PUBLISH = Workflow::PUBLISH_APPROVAL_KIND
  # A post of Halon's pull request review, made once approved and caught up after (PullRequestReviewPosting).
  KIND_PULL_REQUEST_REVIEW = PullRequestReview::RESUME_KIND

  def self.park!(approval, subject, kind)
    approval.update!(resume_payload: {
      kind: kind,
      attrs: subject.resume_attrs,
      channel_id: subject.channel_id,
      user_id: subject.user_id
    })
  end

  def self.park_web!(approval, request, membership:)
    approval.update!(resume_payload: WebRequestReplay.payload_for(request, membership).merge(kind: KIND_WEB))
  end

  # A fix's step is run by a person once approved, never the moment it is, so its approval waits for them.
  def self.park_fix_step!(approval, step)
    approval.update!(resume_payload: { kind: KIND_FIX_STEP, step_id: step.id }, held_for_run: true)
  end

  # A workflow step waits for the decision itself, so its approval is never replayed from here.
  # step_key names the step on the run's record, so the run's page says what it waits for.
  def self.park_workflow_step!(approval, engine_step_id, step_key)
    approval.update!(resume_payload: { kind: KIND_WORKFLOW_STEP, step_id: engine_step_id, step_key: step_key })
  end

  # stage says which call was held, publishing or granting what it needs. revision is the draft as it was asked about.
  def self.park_workflow_publish!(approval, workflow, revision:, source:, stage:)
    approval.update!(resume_payload: { kind: KIND_WORKFLOW_PUBLISH, workflow_id: workflow.id, revision: revision, source: source, stage: stage })
  end

  RUNS_NOW = "It runs now.".freeze
  # A caller with nothing parked, such as an API key or an agent over MCP, makes the call again itself.
  ASKER_RUNS = "They can run it now.".freeze

  # What approving it does next, told to whoever approved it.
  def self.approved_words(approval)
    payload = approval.resume_payload.to_h
    case payload["kind"]
    when KIND_WORKFLOW_STEP then approval.workflow_question? ? "Its run goes on." : "Its run goes on and makes the call."
    when KIND_WORKFLOW_PUBLISH then publish_words(approval, payload)
    when KIND_FIX_STEP then "#{fix_applier(payload)} can run it now."
    when Chat::HeldCall::RESUME_KIND then RUNS_NOW
    when KIND_INTERACTION, KIND_COMMAND, KIND_WEB, KIND_ISSUE_SYNC, KIND_PAGING, KIND_PULL_REQUEST_REVIEW then RUNS_NOW
    else ASKER_RUNS
    end
  end

  # Approving the publish call grants what the workflow needs next, which an approval rule can hold in turn.
  def self.publish_words(approval, payload)
    workflow = Workflow.find_by(id: payload["workflow_id"], workspace_id: approval.workspace_id)
    return "It is published now." unless workflow

    draft = workflow.draft
    granting = payload["stage"] != WorkflowPublishService::STAGE_GRANT && draft && workflow.missing_reach(draft).any?
    granting ? "#{workflow.name} is published now, unless granting what it needs waits on an approval too." : "#{workflow.name} is published now."
  end
  private_class_method :publish_words

  def self.fix_applier(payload)
    Investigation::RemediationStep.find_by(id: payload["step_id"])&.plan&.applier_name || "Whoever applied the fix"
  end
  private_class_method :fix_applier

  # An approval admits one execution. Re-entering the gateway on a consumed
  # approval would park a fresh one, so a job that runs twice must not replay.
  def self.resume!(approval)
    payload = approval.resume_payload
    return if payload.blank? || approval.consumed_at.present?
    return Investigation::FixRunner.resume!(approval, payload["step_id"]) if payload["kind"] == KIND_FIX_STEP
    return decided_workflow_step!(approval, payload) if payload["kind"] == KIND_WORKFLOW_STEP
    return workflow_publish_approved!(approval, payload) if payload["kind"] == KIND_WORKFLOW_PUBLISH
    return Conversation::HeldCalls.approved!(approval) if payload["kind"] == Chat::HeldCall::RESUME_KIND
    return IssueSyncService.new(approval.workspace).decided(approval, payload) if payload["kind"] == KIND_ISSUE_SYNC
    return OnCallSyncService.new(approval.workspace).decided(approval, payload) if payload["kind"] == KIND_PAGING
    return PullRequestReviewPosting.decided(approval, payload) if payload["kind"] == KIND_PULL_REQUEST_REVIEW
    return resume_web!(approval, payload) if payload["kind"] == KIND_WEB

    subject = rebuild(approval, payload)
    return if subject.nil?

    dispatch(payload["kind"], subject)
    notify(approval, payload, "#{approver_name(approval)} approved your request. Going ahead now.")
  rescue StandardError => e
    Rails.logger.warn({ event: "approval.resume_failed", approval_id: approval.id, error: e.message }.to_json)
    notify(approval, payload, "#{approver_name(approval)} approved your request, but Firefight couldn't finish it. Please try again.")
  end

  # The replayed controller's own flash is the outcome, its notice on success,
  # its alert when a guard refused.
  # The workflow is published, or stays the draft it was when the draft changed since, and its card in the chat that
  # made it is redrawn either way.
  def self.workflow_publish_approved!(approval, payload)
    workflow = Workflow.find_by(id: payload["workflow_id"], workspace_id: approval.workspace_id)
    return unless workflow

    result = WorkflowPublishService.new(workflow).publish_approved!(approval, payload)
    Rails.logger.info({ event: "workflow.publish_approved", approval_id: approval.id, workflow_id: workflow.id, published: result.ok }.to_json)
    Conversation::Workflows.moved!(workflow.reload)
  end

  def self.resume_web!(approval, payload)
    result = WebRequestReplay.call(approval, payload)
    if result.success?
      notify(approval, payload, "#{approver_name(approval)} approved your request. #{result.message}")
    else
      Rails.logger.warn({ event: "approval.web_resume_failed", approval_id: approval.id, message: result.message }.to_json)
      notify(approval, payload, "#{approver_name(approval)} approved your request, but Firefight couldn't finish it. #{result.message.presence || 'Please try again.'}")
    end
  rescue StandardError => e
    Rails.logger.warn({ event: "approval.web_resume_failed", approval_id: approval.id, error: e.message }.to_json)
    notify(approval, payload, "#{approver_name(approval)} approved your request, but Firefight couldn't finish it. Please try again.")
  end

  def self.decline!(approval)
    payload = approval.resume_payload
    return if payload.blank?
    return Investigation::FixRunner.resume!(approval, payload["step_id"]) if payload["kind"] == KIND_FIX_STEP
    return decided_workflow_step!(approval, payload) if payload["kind"] == KIND_WORKFLOW_STEP
    return if payload["kind"] == KIND_WORKFLOW_PUBLISH
    return IssueSyncService.new(approval.workspace).decided(approval, payload) if payload["kind"] == KIND_ISSUE_SYNC
    return OnCallSyncService.new(approval.workspace).decided(approval, payload) if payload["kind"] == KIND_PAGING
    return PullRequestReviewPosting.decided(approval, payload) if payload["kind"] == KIND_PULL_REQUEST_REVIEW
    return Conversation::HeldCalls.denied!(approval) if payload["kind"] == Chat::HeldCall::RESUME_KIND

    notify(approval, payload, "#{approver_name(approval)} declined your request. Nothing has changed.")
  end

  # An approved call that waited for a person to run it, and nobody did within its window.
  def self.lapsed!(approval)
    payload = approval.resume_payload
    return if payload.blank?
    return Investigation::FixRunner.lapsed!(approval, payload["step_id"]) if payload["kind"] == KIND_FIX_STEP

    Conversation::HeldCalls.expired!(approval) if payload["kind"] == Chat::HeldCall::RESUME_KIND
  end

  # The step that waited wakes with the decision and goes on from there.
  def self.decided_workflow_step!(approval, payload)
    DefinedWorkflow.deliver!(payload["step_id"], "#{DefinedWorkflow::Steps::CallTool::APPROVAL}:#{approval.id}", { status: approval.status })
  end

  def self.rebuild(approval, payload)
    attrs = payload.fetch("attrs", {})

    case payload["kind"]
    when KIND_INTERACTION
      Interaction.new(attrs.merge("approval_id" => approval.id))
    when KIND_COMMAND
      # Command reads metadata with symbol keys, and the round trip through
      # jsonb turns them into strings.
      Command.new(attrs.merge("metadata" => attrs.fetch("metadata", {}).symbolize_keys,
                              "approval_id" => approval.id))
    end
  end
  private_class_method :rebuild

  def self.dispatch(kind, subject)
    kind == KIND_INTERACTION ? InteractionDispatcher.dispatch(subject) : CommandDispatcher.dispatch(subject)
  end
  private_class_method :dispatch

  def self.approver_name(approval)
    approval.approver&.actor_display_name || "A workspace admin"
  end
  private_class_method :approver_name

  # A chat request is answered where it was made. A dashboard request has no
  # page left, so the requester gets a direct message.
  def self.notify(approval, payload, text)
    return if payload.blank?

    adapter = WorkspaceAdapter.for(approval.workspace)
    if payload["kind"] == KIND_WEB
      membership = approval.workspace.workspace_memberships.find_by(id: payload["membership_id"])
      return if membership&.platform_user_id.blank?

      adapter.post_direct_message(user_id: membership.platform_user_id, text: text)
    else
      channel_id = payload["channel_id"]
      user_id = payload["user_id"]
      return if channel_id.blank? || user_id.blank?

      adapter.post_ephemeral(channel_id: channel_id, user_id: user_id, text: text)
    end
  rescue AdapterError => e
    Rails.logger.warn({ event: "approval.resume_notify_failed", approval_id: approval.id, error: e.class.name }.to_json)
  end
  private_class_method :notify
end
