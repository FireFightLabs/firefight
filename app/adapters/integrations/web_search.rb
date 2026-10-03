module Integrations
  # Where Halon and a coding agent read the public web, on Firefight's own keys. Each provider only searches and reads
  # a page, and answers the same shapes, so trying another is a setting. The first provider in the order that has a key
  # answers, and the next one takes over when it fails.
  module WebSearch
    class Error < Integrations::Error; end
    class NotConfigured < Error; end
    # The provider turned down what we asked, so another would too, and is not tried.
    class Refused < Error; end

    Result = Data.define(:title, :url, :text)
    Page = Data.define(:url, :text)

    PROVIDER_TAVILY = "tavily".freeze
    PROVIDER_FIRECRAWL = "firecrawl".freeze
    PROVIDERS = [ PROVIDER_TAVILY, PROVIDER_FIRECRAWL ].freeze
    MAX_RESULTS = 8
    # No provider is started after this, so a lookup never holds a request for two providers' worth of waiting.
    FALLBACK_WITHIN = 45.seconds
    REFUSED_CODES = [ 400, 422 ].freeze
    NOT_CONFIGURED = "Web search is not set up on this Firefight (TAVILY_API_KEY or FIRECRAWL_API_KEY).".freeze

    def self.search(query, domains: []) = first_answer(order("WEB_SEARCH_PROVIDERS")) { |provider| provider.search(query, domains: domains) }

    # Read in its own order, since one provider can be better at searching and another at reading a page.
    def self.read(url) = first_answer(order("WEB_READ_PROVIDERS")) { |provider| provider.read(url) }

    # The providers named in the setting, in its order, Tavily then Firecrawl when it is not set.
    def self.order(setting)
      names = ENV[setting].to_s.split(",").map(&:strip).compact_blank.uniq.presence || PROVIDERS
      unknown = names - PROVIDERS
      raise Error, "#{setting} names #{unknown.join(', ')}, which is not one of #{PROVIDERS.join(', ')}." if unknown.any?

      names.map { |name| provider(name) }
    end

    def self.provider(name) = name == PROVIDER_FIRECRAWL ? Firecrawl.new : Tavily.new

    # Checked when the app boots, so a mistyped order fails the deploy rather than every lookup.
    def self.check_order!
      order("WEB_SEARCH_PROVIDERS")
      order("WEB_READ_PROVIDERS")
    end

    def self.first_answer(providers)
      ready = providers.select(&:configured?)
      raise NotConfigured, NOT_CONFIGURED if ready.empty?

      started = Time.current
      ready.each_with_index do |provider, index|
        answer = yield(provider)
        Rails.logger.info({ event: "web_lookup.answered", provider: provider.name, fallback: index.positive? }.to_json)
        return answer
      rescue Refused
        raise
      rescue Error => error
        Rails.logger.warn({ event: "web_lookup.provider_failed", provider: provider.name, error: error.message.truncate(200) }.to_json)
        raise if provider == ready.last || Time.current - started > FALLBACK_WITHIN
      end
    end
    private_class_method :first_answer, :provider
  end
end
