class SeverityOptionSerializer < BaseSerializer
  attributes(
    name: { type: :string },
    slug: { type: :string }
  )
end
