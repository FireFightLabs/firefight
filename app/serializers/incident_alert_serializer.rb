class IncidentAlertSerializer < BaseSerializer
  object_as :alert

  type :string
  def id
    alert.id
  end

  attributes(
    status: { type: :string },
    event_count: { type: :number }
  )

  type :string
  def title
    alert.title
  end

  type :string
  def source_name
    alert.alert_source.name
  end

  type :string
  def last_seen_at
    alert.last_seen_at.utc.iso8601
  end
end
