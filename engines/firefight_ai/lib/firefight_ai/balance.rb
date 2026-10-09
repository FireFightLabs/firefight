module FirefightAi
  # What is left on the deployment's keys, in dollars, for the providers whose API says. Each such provider has one
  # reader in READERS, and a provider without one has nothing to read.
  module Balance
    TIMEOUT = 10

    # What a key itself may still spend. remaining is nil when the key has no spending limit of its own, so it spends
    # whatever the account holds, which a key that makes calls cannot read.
    Key = Data.define(:remaining, :usage) do
      def unlimited? = remaining.nil?
    end

    # OpenRouter says what an account holds through its credits endpoint, which takes only a management key, and what a
    # key may still spend through its key endpoint, which takes the key itself.
    module OpenRouter
      BASE = "https://openrouter.ai/api/v1".freeze

      module_function

      def remaining
        data = Balance.get_json("#{base}/credits", key)
        data && (data.dig("data", "total_credits").to_f - data.dig("data", "total_usage").to_f)
      end

      def key_balance
        data = Balance.get_json("#{base}/key", key)&.dig("data")
        return nil unless data

        Key.new(remaining: data["limit_remaining"]&.to_f, usage: data["usage"].to_f)
      end

      def key = FirefightAi.configuration.provider_settings[:openrouter_api_key]

      def base = FirefightAi.configuration.provider_settings[:openrouter_api_base].presence || BASE
    end

    READERS = { "openrouter" => OpenRouter }.freeze

    module_function

    def providers = READERS.keys

    # The account's balance. Nil when the provider has no balance to read, its key is not set, or the read failed.
    def remaining(provider)
      reader = READERS[provider.to_s]
      reader.remaining if reader&.key.present?
    end

    # What the key calls are made with may still spend, as a Key. Nil the same way as remaining.
    def key(provider)
      reader = READERS[provider.to_s]
      reader.key_balance if reader&.key.present?
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
