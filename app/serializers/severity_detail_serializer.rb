class SeverityDetailSerializer < BaseSerializer
  attributes(
    name: { type: :string },
    rank: { type: :number },
    color: { type: :string }
  )
end
