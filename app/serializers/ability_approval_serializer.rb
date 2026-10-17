class AbilityApprovalSerializer < BaseSerializer
  object_as :approval

  STATUS_UNION = Ability::Approval::STATUSES.map(&:inspect).join(" | ")

  type :string
  def id
    approval.id
  end

  # Who asked or acted as a person reads it, such as "Halon", never the machine label the row keeps.
  type :string
  def principal_name
    approval.principal_name
  end

  attributes(
    action_key: { type: :string },
    required_role: { type: :string },
    self_approvable: { type: :boolean }
  )

  type STATUS_UNION
  def status
    approval.status
  end

  type "Record<string, string[]>"
  def scope
    approval.scope
  end

  # A command typed in the chat platform reads as the platform shows it, from the platform_texts handed in.
  type "Record<string, unknown>"
  def params
    approval.params_shown(options.fetch(:platform_texts, {}))
  end

  type "{ kind: string; id: string }[]"
  def approvers
    Ability::Principal.references(approval.approver_ids)
  end

  type :string, optional: true
  def approver_name
    approval.decider_name
  end

  # The connection a tool's action runs through, as a person tells it apart, such as "Production (Acme Cloud)".
  type :string, optional: true
  def connection
    approval.connection_name
  end

  type :string, optional: true
  def source
    approval.source
  end

  # What a workflow's Approval step asks, and what it said approvers should know, in place of a call's params.
  type :string, optional: true
  def question
    approval.question
  end

  type :string, optional: true
  def question_details
    approval.question_details
  end

  # Why the person looking may not decide it, as the gateway answers, or nil when they may, through approvals access or
  # being named on the workflow Approval step that asked it. Only a request still waiting is asked, given who is looking.
  type :string, optional: true
  def decide_denied_reason
    approval.decide_denied_reason(options[:member]) if options[:member] && approval.pending?
  end

  type :string, optional: true
  def source_label
    Ability::Source.label(approval.source)
  end

  # What a counted database write touches, each a label and what it says, as the asker's card would have shown it.
  type "string[][]"
  def rows = shown.rows

  # The warning about text read from outside Firefight before the call, as the asker's card would have carried it.
  type :string, optional: true
  def caution = shown.caution

  def shown = memo.fetch(:shown) { ApprovalNotificationService.shown(approval) }

  type :string
  def created_at
    approval.created_at.iso8601
  end

  type :string, optional: true
  def resolved_at
    approval.resolved_at&.iso8601
  end
end
