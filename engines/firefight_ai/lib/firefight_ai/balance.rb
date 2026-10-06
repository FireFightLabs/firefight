module FirefightAi
  # What is left on the deployment's account with a provider, in dollars, for the providers that say. OpenRouter says
  # through its credits endpoint, read with the key calls are made with. A key it refuses there reads as nothing, and
  # the account then waits for its next answered call.
  module Balance
    OPENROUTER = "openrouter".freeze
    OPENROUTER_BASE = "https://openrouter.ai/api/v1".freeze
    TIMEOUT = 10

    module_function

    # Nil when the provider has no balance to read, its key is not set, or the read failed.
    def remaining(provider)
      return nil unless provider.to_s == OPENROUTER

      key = FirefightAi.configuration.provider_settings[:openrouter_api_key]
      return nil if key.blank?

      data = get_json("#{FirefightAi.configuration.provider_settings[:openrouter_api_base].presence || OPENROUTER_BASE}/credits", key)
      data && (data.dig("data", "total_credits").to_f - data.dig("data", "total_usage").to_f)
    end

    def get_json(address, key)
      uri = URI.parse(address)
      request = Net::HTTP::Get.new(uri, "Authorization" => "Bearer #{key}")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.request(request)
      end
      response.is_a?(Net::HTTPSuccess) ? JSON.parse(response.body) : nil
    rescue StandardError => e
      Rails.logger.warn({ event: "ai.balance_unread", error_class: e.class.name }.to_json)
      nil
    end
  end
end
