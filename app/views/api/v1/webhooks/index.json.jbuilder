json.webhooks @webhooks do |webhook|
  json.partial! "api/v1/webhooks/webhook", webhook: webhook
end
