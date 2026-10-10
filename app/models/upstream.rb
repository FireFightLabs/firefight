# An outside system an app may depend on, such as its payment, email or sign-in provider, or one of the providers
# Firefight connects to. Each has a public status page and the domains its API answers on, so an error naming one of
# them points at it, and a setting naming it says the app uses it. Registry data: the providers Firefight connects to
# from config/integration_providers.yml, and the rest from config/upstreams.yml.
class Upstream
  REGISTRY_PATH = Rails.root.join("config/upstreams.yml")

  # A status page is read as the Statuspage summary it publishes as JSON, or as the page itself through web reading.
  FEED_STATUSPAGE = "statuspage".freeze
  FEED_PAGE = "page".freeze
  FEEDS = [ FEED_STATUSPAGE, FEED_PAGE ].freeze
  SUMMARY_PATH = "/api/v2/summary.json".freeze

  StatusPage = Data.define(:url, :feed) do
    def initialize(url:, feed:)
      raise ArgumentError, "a status page's feed is one of #{FEEDS.join(', ')}, not #{feed.inspect}" unless FEEDS.include?(feed.to_s)
      raise ArgumentError, "a status page is an https address, not #{url.inspect}" unless url.to_s.start_with?("https://")

      super(url: url.to_s.delete_suffix("/"), feed: feed.to_s)
    end

    def summary_url = "#{url}#{SUMMARY_PATH}"

    def statuspage? = feed == FEED_STATUSPAGE

    # The registry's status_page, or nil when it lists none.
    def self.from(raw)
      page = raw["status_page"]
      page && new(url: page.fetch("url"), feed: page.fetch("feed"))
    end
  end

  # provider is the key of the integration provider Firefight connects it with, or nil when there is none.
  Entry = Data.define(:key, :name, :category, :status_page, :hosts, :setting_words, :provider) do
    def connectable? = provider.present?

    # Whether a host is one of its domains or a name under one.
    def answers_on?(host)
      host = host.to_s.downcase.delete_suffix(".")
      hosts.any? { |each| host == each || host.end_with?(".#{each}") }
    end

    # The most specific of its domains a host is under, for telling two providers sharing a parent domain apart.
    def matched_length(host) = hosts.select { |each| host == each || host.end_with?(".#{each}") }.map(&:length).max.to_i
  end

  def self.all
    @all ||= (provider_entries + listed).freeze
  end

  def self.provider_entries
    IntegrationProvider.all.filter_map do |provider|
      next unless provider.status_page || provider.hosts.any? || provider.setting_words.any?

      Entry.new(key: provider.key, name: provider.name, category: provider.category, status_page: provider.status_page,
                hosts: provider.hosts, setting_words: provider.setting_words, provider: provider.key)
    end
  end

  def self.listed
    raw = YAML.safe_load_file(REGISTRY_PATH)
    categories = raw.fetch("categories")
    raw.fetch("upstreams").map do |entry|
      key = entry.fetch("key")
      raise ArgumentError, "#{key} is a provider Firefight connects to, so it is listed in config/integration_providers.yml" if IntegrationProvider.find(key)
      raise ArgumentError, "#{key} names category #{entry['category'].inspect}, one of #{categories.join(', ')}" unless categories.include?(entry["category"])

      words = Array(entry["setting_words"]).map(&:to_s)
      raise ArgumentError, "#{key}'s setting words are whole words in capitals" unless words.all? { |word| word.match?(/\A[A-Z][A-Z0-9]+\z/) }

      Entry.new(key: key, name: entry.fetch("name"), category: entry.fetch("category"), status_page: StatusPage.from(entry),
                hosts: hosts_of(entry), setting_words: words, provider: nil)
    end
  end
  private_class_method :provider_entries, :listed

  def self.hosts_of(raw) = Array(raw["hosts"]).map { |host| host.to_s.downcase.strip }.compact_blank

  def self.categories = YAML.safe_load_file(REGISTRY_PATH).fetch("categories")

  def self.find(key) = all.find { |entry| entry.key == key.to_s }

  # By its key or its name, as a person or a model names it, ignoring case.
  def self.named(text)
    wanted = text.to_s.strip.downcase
    return if wanted.empty?

    all.find { |entry| entry.key == wanted || entry.name.downcase == wanted } ||
      all.find { |entry| entry.name.downcase.split(/\s+and\s+/).include?(wanted) }
  end

  # The system a host belongs to, the one naming the most specific of its domains when two share a parent.
  def self.for_host(host)
    host = host.to_s.downcase.strip.delete_suffix(".")
    return if host.empty?

    all.select { |entry| entry.answers_on?(host) }.max_by { |entry| entry.matched_length(host) }
  end

  # Words in a setting's name that say the app uses an outside system, for the map to keep the setting by its name.
  def self.setting_words = @setting_words ||= all.flat_map(&:setting_words).uniq.freeze

  # The systems a setting's name points at, by its words.
  def self.for_setting(name)
    words = ResourceMap::Use.words(name)
    all.select { |entry| entry.setting_words.intersect?(words) }
  end

  # A line that says a call failed: a timeout, a refused or reset connection, a name that did not resolve, a TLS
  # failure or a 5xx from the other side.
  FAILURE = /time[ds]?[ _-]?out|timeout|ETIMEDOUT|ECONNRESET|ECONNREFUSED|EHOSTUNREACH|ENOTFOUND|EAI_AGAIN|getaddrinfo|
             connection (?:refused|reset|closed)|could not (?:connect|resolve)|failed to connect|SSL|TLS|certificate|
             \b5\d\d\b|service unavailable|bad gateway|gateway time|upstream|unreachable|rate limit|too many requests|
             \berror\b|\bfailed\b|exception/ix
  HOST = /\b(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24}\b/i
  # The most systems one result points at, so a log full of hosts never turns into a page of status reads.
  POINTED_AT_MOST = 3

  # The outside systems failing lines in a result name, by host, most named first, with a host each was named by.
  Pointed = Data.define(:entry, :host, :lines)

  def self.pointed_at(text)
    found = Hash.new { |hash, key| hash[key] = { hosts: Hash.new(0), lines: 0 } }
    text.to_s.each_line do |line|
      next unless line.match?(FAILURE)

      line.scan(HOST).uniq.each do |host|
        entry = for_host(host)
        next unless entry&.status_page

        found[entry.key][:hosts][host.downcase] += 1
        found[entry.key][:lines] += 1
      end
    end
    found.sort_by { |_key, seen| -seen[:lines] }.first(POINTED_AT_MOST).map do |key, seen|
      Pointed.new(entry: find(key), host: seen[:hosts].max_by(&:last).first, lines: seen[:lines])
    end
  end
end
