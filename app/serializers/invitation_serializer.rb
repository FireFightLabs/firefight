class InvitationSerializer < BaseSerializer
  object_as :invitation

  type :string
  def id
    invitation.id
  end

  attributes(
    email: { type: :string }
  )

  type :string
  def invited_by
    invitation.invited_by.user.name
  end

  type :string
  def expires_at
    invitation.expires_at.utc.iso8601
  end

  type :string
  def created_at
    invitation.created_at.utc.iso8601
  end
end
