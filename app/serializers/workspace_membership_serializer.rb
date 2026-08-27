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
end
