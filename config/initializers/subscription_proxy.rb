# The subscription proxy (deploy/subscription-proxy), which turns a workspace's AI subscription sign-in into an
# ordinary API. Only the app holds its two keys.
Rails.application.config.x.subscription_proxy = ActiveSupport::OrderedOptions.new.tap do |proxy|
  proxy.url = ENV["SUBSCRIPTION_PROXY_URL"].presence
  proxy.client_key = ENV["SUBSCRIPTION_PROXY_CLIENT_KEY"].presence
  proxy.management_key = ENV["SUBSCRIPTION_PROXY_MANAGEMENT_KEY"].presence
end
