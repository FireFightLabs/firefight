module FirefightAi
  # What is left on the deployment's own accounts, in dollars, for the providers whose API says. Each such provider has
  # one reader in READERS, and a provider without one has nothing to read.
  module Balance
    TIMEOUT = 10

    # What the account holds and has spent in all, in dollars.
    Account = Data.define(:remaining, :usage)

    # OpenRouter says what an account holds only through its credits endpoint, which takes a management key, never the
    # key calls are made with. OPENROUTER_MANAGEMENT_KEY holds one, read-only use is all it gets here.
    module OpenRouter
      BASE = "https://openrouter.ai/api/v1".freeze

      module_function

      def account
        data = Balance.get_json("#{base}/credits", balance_key)&.dig("data")
        return nil unless data

        credits = data["total_credits"].to_f
        usage = data["total_usage"].to_f
        Account.new(remaining: credits - usage, usage: usage)
      end

      # Whether the deployment makes calls on OpenRouter at all.
      def used? = FirefightAi.configuration.provider_settings[:openrouter_api_key].present?

      def balance_key = FirefightAi.configuration.openrouter_management_key

      def balance_key_name = "OPENROUTER_MANAGEMENT_KEY"

      def base = FirefightAi.configuration.provider_settings[:openrouter_api_base].presence || BASE
    end

    READERS = { "openrouter" => OpenRouter }.freeze

    module_function

    def providers = READERS.keys

    # The account's balance as an Account. Nil when the provider has no balance to read, the key that reads it is not
    # set, or the read failed.
    def account(provider)
      reader = READERS[provider.to_s]
      reader.account if readable?(provider)
    end

    def remaining(provider) = account(provider)&.remaining

    def readable?(provider) = READERS[provider.to_s]&.balance_key.present?

    # The providers the deployment calls whose balance goes unchecked because the key that reads it is not set, each
    # with that key's env var name.
    def unchecked
      READERS.filter_map { |provider, reader| [ provider, reader.balance_key_name ] if reader.used? && reader.balance_key.blank? }.to_h
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
