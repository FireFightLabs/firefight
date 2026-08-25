class AbilityApprovalSerializer < BaseSerializer
  object_as :approval

  STATUS_UNION = Ability::Approval::STATUSES.map(&:inspect).join(" | ")

  type :string
  def id
    approval.id
  end

  attributes(
    principal_label: { type: :string },
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

  type "Record<string, unknown>"
  def params
    approval.params
  end

  type "{ kind: string; id: string }[]"
  def approvers
    Ability::Principal.references(approval.approver_ids)
  end

  type :string, optional: true
  def approver_name
    approval.approver&.actor_display_name
  end

  type :string, optional: true
  def source
    approval.source
  end

  type :string
  def created_at
    approval.created_at.iso8601
  end

  type :string, optional: true
  def resolved_at
    approval.resolved_at&.iso8601
  end
end
