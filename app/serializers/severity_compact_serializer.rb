class SeverityCompactSerializer < BaseSerializer
  attributes(
    name: { type: :string },
    rank: { type: :number },
    color: { type: :string, optional: true }
  )
end
