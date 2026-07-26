class EnvironmentOptionSerializer < BaseSerializer
  object_as :environment

  type :string
  def id
    environment.id
  end

  attributes(
    name: { type: :string },
    slug: { type: :string }
  )
end
