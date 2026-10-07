class SignInMethodSerializer < BaseSerializer
  object_as :identity

  type :string
  def id
    identity.id.to_s
  end

  attributes(
    provider: { type: :string },
    label: { type: :string }
  )

  type :string, optional: true
  def email
    identity.email
  end

  type :string, optional: true
  def last_used_at
    identity.last_used_at&.iso8601
  end

  type :string
  def added_at
    identity.created_at.iso8601
  end

  type :string, optional: true
  def removal_blocked_reason
    identity.removal_blocked_reason
  end
end
