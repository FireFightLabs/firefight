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

  # The secret itself is shown once when made or replaced, never in a page's props.
  type :string
  def signing_secret_hint
    webhook.signing_secret_hint
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
