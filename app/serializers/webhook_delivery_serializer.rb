class WebhookDeliverySerializer < BaseSerializer
  object_as :delivery

  type :string
  def id
    delivery.id
  end

  STATE_UNION = WebhookDelivery.states.keys.map(&:inspect).join(" | ")

  attributes(
    event_type: { type: :string },
    response_code: { type: :number, optional: true },
    error_message: { type: :string, optional: true }
  )

  type STATE_UNION
  def state
    delivery.state
  end

  type :string
  def attempted_at
    delivery.created_at.utc.iso8601
  end

  type :string, optional: true
  def delivered_at
    delivery.delivered_at&.utc&.iso8601
  end
end
