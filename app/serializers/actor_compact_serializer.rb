# One actor, wherever the dashboard shows one. The lead, a role holder,
# whoever declared the incident. They all render the same chip, so they all
# serialize the same way, and an agent is an actor too, with a name and no
# face, which the optional avatar already allows for.
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

  # What the reader is looking at, so a chip can mark a machine as one rather
  # than passing it off as a colleague. Typed as the kinds themselves, so a
  # frontend lookup keyed by kind needs no cast.
  type KIND_UNION
  def kind
    actor.actor_kind
  end
end
