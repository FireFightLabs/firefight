class IncidentLeadSerializer < BaseSerializer
  object_as :member

  type :string
  def name
    member.user.name
  end

  type :string
  def initials
    member.user.name.split.map { |n| n[0] }.join.upcase
  end

  type :string, optional: true
  def avatar_url
    member.user.avatar_url
  end
end
