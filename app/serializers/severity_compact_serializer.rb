class SeverityCompactSerializer < BaseSerializer
  attributes(
    name: { type: :string },
    rank: { type: :number }
  )
end
