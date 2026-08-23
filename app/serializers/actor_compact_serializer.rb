# One person, wherever the dashboard shows one, the lead, a role holder, whoever
# declared the incident. They all render the same chip, so they all serialize the
# same way.
class ActorCompactSerializer < BaseSerializer
  object_as :member

  type :string
  def name
    member.user.name
  end

  type :string
  def initials
    member.user.name.split.map { |part| part[0] }.join.upcase
  end

  type :string, optional: true
  def avatar_url
    member.user.avatar_url
  end
end
