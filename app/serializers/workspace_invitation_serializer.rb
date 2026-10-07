class WorkspaceInvitationSerializer < BaseSerializer
  object_as :invitation

  type :string
  def id
    invitation.id
  end

  attributes(
    email: { type: :string }
  )

  type :string, optional: true
  def invited_by_name
    invitation.invited_by&.display_name
  end

  type :string
  def sent_at
    invitation.last_sent_at.utc.iso8601
  end

  type :string
  def expires_at
    invitation.expires_at.utc.iso8601
  end

  type :boolean
  def expired
    invitation.expired?
  end
end
