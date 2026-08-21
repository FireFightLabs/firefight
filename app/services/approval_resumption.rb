# Slack has no retry. The API and MCP park a call and let the caller re-issue
# it with the approval id, but a person who clicked a button cannot, so the
# request is stored when it parks and replayed once someone approves.
class ApprovalResumption
  KIND_INTERACTION = "interaction"
  KIND_COMMAND = "command"

  def self.park!(approval, subject, kind)
    approval.update!(resume_payload: {
      kind: kind,
      attrs: subject.resume_attrs,
      channel_id: subject.channel_id,
      user_id: subject.user_id
    })
  end

  # An approval admits exactly one execution, so a job that runs twice must not
  # replay the request again. Re-entering the gateway on a consumed approval
  # would not match it and would park a fresh one.
  def self.resume!(approval)
    payload = approval.resume_payload
    return if payload.blank? || approval.consumed_at.present?

    subject = rebuild(approval, payload)
    return if subject.nil?

    dispatch(payload["kind"], subject)
    notify(approval, payload, "#{approver_name(approval)} approved your request. Going ahead now.")
  rescue StandardError => e
    Rails.logger.warn({ event: "approval.resume_failed", approval_id: approval.id, error: e.message }.to_json)
    notify(approval, payload, "#{approver_name(approval)} approved your request, but Firefight couldn't finish it. Please try again.")
  end

  def self.decline!(approval)
    payload = approval.resume_payload
    return if payload.blank?

    notify(approval, payload, "#{approver_name(approval)} declined your request. Nothing has changed.")
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
    approval.approver&.display_name || "A workspace admin"
  end
  private_class_method :approver_name

  def self.notify(approval, payload, text)
    channel_id = payload && payload["channel_id"]
    user_id = payload && payload["user_id"]
    return if channel_id.blank? || user_id.blank?

    WorkspaceAdapter.for(approval.workspace).post_ephemeral(channel_id: channel_id, user_id: user_id, text: text)
  rescue AdapterError => e
    Rails.logger.warn({ event: "approval.resume_notify_failed", approval_id: approval.id, error: e.class.name }.to_json)
  end
  private_class_method :notify
end
