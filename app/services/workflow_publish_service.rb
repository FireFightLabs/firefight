# Publishing a workflow, and a member asking an admin to. Publishing makes the draft live, grants the workflow's own
# identity exactly what its steps need (as the admin publishing), and sets when it runs next. The caller authorized it
# as workflows.update, and permissions.create when anything is to be granted. A member asks instead: every admin gets a
# direct message with Publish, at most once a day for the same member and workflow, and the Workflows page lists what
# waits. However it is published, each request for it is settled and its member told.
class WorkflowPublishService
  Result = Data.define(:ok, :words)
  NO_ADMIN_REACHED = "No admin could be reached by direct message, so the request waits on the Workflows page.".freeze

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

  # Publish pressed on a member's request, from the platform. The draft as it is now is published.
  def publish_requested!(request, by:)
    return Result.new(ok: false, words: "Workflows are not switched on for this workspace.") unless FeatureFlags.enabled?(@workspace, FeatureFlags::WORKFLOWS)
    return Result.new(ok: false, words: "This request was already answered.") unless request.waiting?

    draft = @workflow.draft
    return Result.new(ok: false, words: "#{@workflow.name} has no draft to publish any more.") unless draft

    publish!(draft, by: by)
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
