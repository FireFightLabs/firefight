class CurrentUserSerializer < BaseSerializer
  object_as :user

  type :string
  def id
    user.id.to_s
  end

  attributes(
    name: { type: :string },
    email: { type: :string }
  )

  type :string, optional: true
  def avatar_url
    user.avatar_url
  end
end
