class ActorCompactSerializer < BaseSerializer
  object_as :member

  type :string
  def name
    member.user.name
  end
end
