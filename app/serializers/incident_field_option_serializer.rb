class IncidentFieldOptionSerializer < BaseSerializer
  object_as :option

  attributes(
    id: { type: :string },
    label: { type: :string },
    position: { type: :number }
  )

  type :boolean
  def enabled
    option.enabled?
  end

  type :number
  def usage_count
    option.usage_count
  end

  type :string, optional: true
  def deletion_blocked_reason
    option.deletion_blocked_reason
  end
end
