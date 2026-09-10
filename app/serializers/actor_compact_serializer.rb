# Every actor renders the same chip, so every actor serializes the same way. An agent
# has a name and no face, which the optional avatar allows.
class ActorCompactSerializer < BaseSerializer
  object_as :actor

  type :string
  def name
    actor.actor_display_name
  end

  type :string
  def initials
    actor.actor_display_name.split.map { |part| part[0] }.join.upcase
  end

  type :string, optional: true
  def avatar_url
    return nil unless actor.respond_to?(:user)

    actor.user&.avatar_url
  end

  KIND_UNION = Ability::Principal::KINDS.map(&:inspect).join(" | ")

  # Marks a machine as one. Typed as the kinds so a frontend lookup needs no cast.
  type KIND_UNION
  def kind
    actor.actor_kind
  end
end
