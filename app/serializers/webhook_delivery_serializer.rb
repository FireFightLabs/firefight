class WebhookDeliverySerializer < BaseSerializer
  object_as :delivery

  type :string
  def id
    delivery.id
  end

  attributes(
    event_type: { type: :string },
    state: { type: '"completed" | "errored"' },
    response_code: { type: :number, optional: true },
    error_message: { type: :string, optional: true }
  )

  type :string
  def delivered_at
    (delivery.delivered_at || delivery.created_at).utc.iso8601
  end
end
