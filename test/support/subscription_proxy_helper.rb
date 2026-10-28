# The subscription proxy as tests see it: configured with made-up keys, and answering through a stubbed transport.
module SubscriptionProxyHelper
  PROXY_URL = "http://subscription-proxy.internal:8317".freeze

  def configure_subscription_proxy!
    SubscriptionProxy.stubs(:settings).returns(
      ActiveSupport::OrderedOptions.new.merge!(url: PROXY_URL, client_key: "client-key", management_key: "management-key")
    )
  end

  def proxy_response(code, body = {}, headers = {})
    klass = Net::HTTPResponse::CODE_TO_OBJ.fetch(code.to_s)
    klass.new("1.1", code.to_s, "").tap do |response|
      response.instance_variable_set(:@body, body.is_a?(String) ? body : body.to_json)
      response.instance_variable_set(:@read, true)
      headers.each { |name, value| response[name] = value }
    end
  end

  # Answers the requests in turn with these responses, and answers the requests that were sent.
  def stub_proxy(*answers)
    sent = []
    SubscriptionProxy::Client.any_instance.stubs(:transport).with do |_uri, request|
      sent << request
      true
    end.returns(*answers)
    sent
  end
end
