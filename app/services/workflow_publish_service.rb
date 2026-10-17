# Publishing a workflow, and a member asking an admin to. Publishing makes the draft live, grants the workflow's own
# identity exactly what its steps need (as the admin publishing), and sets when it runs next. The caller authorized it
# as workflows.update, and permissions.create when anything is to be granted. A member asks instead, and every admin gets a
# direct message with Publish, at most once a day for the same member and workflow, and the Workflows page lists what
# waits. However it is published, each request for it is settled and its member told.
class WorkflowPublishService
  Result = Data.define(:ok, :words)
  NO_ADMIN_REACHED = "No admin could be reached by direct message, so the request waits on the Workflows page.".freeze
  # Said when an approval rule holds publishing a workflow an agent just made, which stays the draft it was made as until
  # an admin approves, and is then published as it was asked about.
  PUBLISH_HELD = "Publishing it is held for an approval, so it waits as a draft and is published once an admin approves.".freeze
  # Which call an approval held: publishing, or granting the identity what it needs once publishing was allowed.
  STAGE_PUBLISH = "publish".freeze
  STAGE_GRANT = "grant".freeze

  def initialize(workflow)
    @workflow = workflow
    @workspace = workflow.workspace
  end

  def publish!(version, by:, revision: version.revision)
    @workflow.ensure_agent!
    ActiveRecord::Base.transaction do
      version.publish!(by: by, revision: revision)
      @workflow.grant_reach!(version, by: by)
      @workflow.reload.schedule!
    end
    settle!(by: by)
    Result.new(ok: true, words: "#{@workflow.name} was published.")
  rescue Workflow::Edit::Refused => refused
    Result.new(ok: false, words: refused.message)
  end

  # Whether by may publish this draft: change a live workflow and, when it needs anything granted, grant it.
  def may_publish?(draft, by:)
    return false unless by.respond_to?(:may?) && by.may?(Ability::Action::RESOURCE_WORKFLOWS, Ability::Action::ACTION_UPDATE, @workspace)

    @workflow.missing_reach(draft).empty? || by.may?(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_CREATE, @workspace)
  end

  def unpublishable_words(draft)
    problem = draft.problems.first
    "#{@workflow.name} waits as a draft, since it cannot be published yet. #{problem}" if problem
  end

  # A member who may not publish asks the admins instead. Anyone else, such as an agent, leaves it a draft.
  def ask_or_leave!(draft, by:)
    return Result.new(ok: false, words: "#{@workflow.name} waits as a draft until a workspace admin publishes it.") unless by.is_a?(WorkspaceMembership)

    ask!(Workflow::PublishRequest.for!(by, @workflow, draft), by: by)
  end

  # Publishing as an agent asks for it, from a chat or over MCP: changing a live workflow and, when it needs anything
  # granted, granting it, each its own call through the gateway as principal. An approval rule holding either keeps the
  # draft, and the approval carries exactly this revision, so approving it publishes that and nothing changed since.
  def publish_through_gateway!(draft, principal:, source:, revision: draft.revision, approval_id: nil, stage: STAGE_PUBLISH)
    granting = @workflow.missing_reach(draft).any?
    publish = -> { publish!(draft, by: principal, revision: revision) }
    grant = ->(approved) { call_as(principal, Workflow::GRANT_KEY, revision, source, approved) { publish.call } }
    return grant.call(approval_id) if stage == STAGE_GRANT

    call_as(principal, Workflow::PUBLISH_KEY, revision, source, approval_id) { granting ? grant.call(nil) : publish.call }
  rescue AbilityGateway::PendingApproval => held
    ApprovalResumption.park_workflow_publish!(held.approval, @workflow, revision: revision, source: source,
                                              stage: held.approval.action_key == Workflow::GRANT_KEY ? STAGE_GRANT : STAGE_PUBLISH)
    Result.new(ok: false, words: PUBLISH_HELD)
  end

  # Approved publishing: the draft at the revision it was asked about, as whoever asked.
  def publish_approved!(approval, payload)
    draft = @workflow.draft
    return Result.new(ok: false, words: Workflow.publish_approval_blocked_reason(approval)) unless draft && draft.revision == payload["revision"]

    publish_through_gateway!(draft, principal: approval.principal, source: payload["source"], revision: payload["revision"], approval_id: approval.id,
                                    stage: payload["stage"])
  end

  # Publish pressed on a member's request, from the platform or the Workflows page. The draft is published as it was
  # when the admins were asked, never one changed since that nobody looked at.
  def publish_requested!(request, by:)
    return Result.new(ok: false, words: "This request was already answered.") unless request.waiting?

    draft = @workflow.draft
    return Result.new(ok: false, words: "#{@workflow.name} has no draft to publish any more.") unless draft

    stale = request.stale_reason(draft)
    return Result.new(ok: false, words: stale) if stale

    publish!(draft, by: by, revision: request.revision)
  end

  # Turned on or off. On, it runs next at its time, not at once for every time it missed.
  def switch!(on:)
    @workflow.update!(enabled: on)
    @workflow.schedule!
  end

  def ask!(request, by:)
    blocked = request.ask_blocked_reason(by)
    return Result.new(ok: false, words: blocked) if blocked
    return Result.new(ok: false, words: request.reload.ask_blocked_reason || "The admins were already asked.") unless request.claim_ask!

    reached = notify_admins(request)
    admins = Ability::PackRequest.admin_names(@workspace).presence || "the workspace admins"
    Result.new(ok: true, words: [ "Asked #{admins} to publish #{@workflow.name}.", (NO_ADMIN_REACHED unless reached) ].compact.join(" "))
  end

  def dismiss!(request, by:)
    return Result.new(ok: false, words: "This request was already answered.") unless request.dismiss!(by: by)

    answered!(request)
    Result.new(ok: true, words: "#{request.requester.display_name}'s request to publish #{@workflow.name} was dismissed.")
  end

  private

  def call_as(principal, action_key, revision, source, approval_id, &block)
    Chat::ToolCall.run!(workspace: @workspace, principal: principal, action_key: action_key, params: { "workflow" => @workflow.slug, "revision" => revision },
                        context: { source: source, approval_id: approval_id }.compact, &block)
  end

  def settle!(by:)
    @workflow.publish_requests.waiting.find_each do |request|
      answered!(request) if request.published!(by: by)
    end
  end

  # The admins' messages are redrawn and the member is told by direct message.
  def answered!(request)
    adapter = WorkspaceAdapter.for(@workspace)
    request.reload.notifications.each do |notification|
      adapter.update_workflow_publish_request(channel_id: notification["channel_id"], message_id: notification["message_id"], request: request)
    rescue AdapterError => error
      Rails.logger.warn({ event: "workflow_publish_request.redraw_failed", request_id: request.id, error: error.class.name }.to_json)
    end
    return if request.requester.platform_user_id.blank?

    adapter.post_workflow_publish_answer_to_user(user_id: request.requester.platform_user_id, request: request)
  rescue AdapterError => error
    Rails.logger.warn({ event: "workflow_publish_request.answer_undelivered", request_id: request.id, error: error.class.name }.to_json)
  end

  # True when at least one admin was sent the request.
  def notify_admins(request)
    adapter = WorkspaceAdapter.for(@workspace)
    Ability::PackRequest.admins_of(@workspace).select { |admin| admin.platform_user_id.present? }.count do |admin|
      posted = adapter.post_workflow_publish_request_to_user(user_id: admin.platform_user_id, request: request)
      request.add_notification!(channel_id: posted[:channel_id], message_id: posted[:message_id])
      true
    rescue AdapterError => error
      Rails.logger.warn({ event: "workflow_publish_request.undelivered", request_id: request.id, error: error.class.name }.to_json)
      false
    end.positive?
  end
end
