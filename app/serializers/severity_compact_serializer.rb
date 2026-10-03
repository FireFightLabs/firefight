class SeverityCompactSerializer < BaseSerializer
  object_as :severity

  attributes(
    name: { type: :string },
    rank: { type: :number },
    color: { type: :string, optional: true }
  )

  type :number
  def signal_bars
    severity.signal_bars
  end
end
