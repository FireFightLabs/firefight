class WebhookSerializer < BaseSerializer
  object_as :webhook

  type :string
  def id
    webhook.id
  end

  attributes(
    name: { type: :string },
    url: { type: :string },
    active: { type: :boolean }
  )

  type "string[]"
  def subscribed_events
    webhook.subscribed_events
  end

  type :string
  def created_at
    webhook.created_at.utc.iso8601
  end

  has_many :recent_deliveries, as: :deliveries, serializer: WebhookDeliverySerializer

  def recent_deliveries
    webhook.webhook_deliveries.order(created_at: :desc).limit(10)
  end

  type :number
  def delivery_count
    webhook.webhook_deliveries.size
  end
end
