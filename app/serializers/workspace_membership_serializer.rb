class WorkspaceMembershipSerializer < BaseSerializer
  object_as :membership

  type :string
  def id
    membership.id
  end

  type :string
  def name
    membership.user.name
  end

  type :string
  def email
    membership.user.email
  end

  type :string, optional: true
  def avatar_url
    membership.user.avatar_url
  end

  attributes(
    role: { type: :string }
  )

  type :string
  def joined_at
    membership.joined_at.utc.iso8601
  end

  # Why the viewer cannot remove this member. The row renders it, the controller refuses with it.
  type :string, optional: true
  def removal_blocked_reason
    membership.removal_blocked_reason(options[:by]) unless membership.removed?
  end

  # Why a removed member cannot be added back.
  type :string, optional: true
  def restore_blocked_reason
    membership.restore_blocked_reason if membership.removed?
  end

  type :string, optional: true
  def removed_at
    membership.removed_at&.utc&.iso8601
  end

  # What removing takes away, named in the confirmation.
  type :number
  def personal_token_count
    membership.live_personal_token_count
  end

  type :number
  def connected_agent_count
    membership.connected_agent_count
  end
end
