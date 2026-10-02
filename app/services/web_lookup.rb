# Reads the public web for Halon and a coding agent, through Tavily on Firefight's key, as text a model reads. Each page
# comes with its address first, so whatever is used from it is cited to where it came from. Another site's words, so
# they are capped and anything that looks like a credential is redacted. What is sent out is checked too, since a search
# or an address is the one way text leaves through here.
module WebLookup
  PAGE_LIMIT = 4_000
  READ_LIMIT = 20_000
  QUERY_LIMIT = 400
  SECRET_REFUSED = "A search or an address must not carry anything that looks like a credential, so it was not sent.".freeze
  # Hosts that only resolve inside a network, never a public page.
  PRIVATE_SUFFIXES = %w[localhost local internal intranet lan corp home arpa].freeze

  def self.search(query, domains: [])
    asked = query.to_s.strip.truncate(QUERY_LIMIT)
    raise ArgumentError, "query is required" if asked.empty?
    raise ArgumentError, SECRET_REFUSED if secret?(asked)

    results = Integrations::Tavily.search(asked, domains: Array(domains).map(&:to_s).first(10))
    return "Nothing found for #{asked}." if results.empty?

    results.each_with_index.map do |result, index|
      text = (result["raw_content"].presence || result["content"]).to_s
      "[#{index + 1}] #{result['title']}\n#{result['url']}\n#{redacted(text).truncate(PAGE_LIMIT)}"
    end.join("\n\n")
  end

  def self.read(url)
    address = url.to_s.strip
    raise ArgumentError, "url must be a public http or https address" unless public?(address)
    raise ArgumentError, SECRET_REFUSED if secret?(address)

    page = Integrations::Tavily.read(address)
    "#{page['url'] || address}\n#{redacted(page['raw_content'].to_s).truncate(READ_LIMIT)}"
  end

  # A plain http or https address with a host name a public page could have, never a raw IP or a private name.
  def self.public?(address)
    uri = URI.parse(address)
    host = uri.host.to_s.downcase
    return false unless %w[http https].include?(uri.scheme) && uri.userinfo.nil? && host.include?(".")
    return false if PRIVATE_SUFFIXES.include?(host.split(".").last) || ip?(host)

    true
  rescue URI::InvalidURIError
    false
  end

  # Any address that is a number in some form, since a public page is named, and a number can reach inside a network.
  def self.ip?(host)
    IPAddr.new(host.delete("[]"))
    true
  rescue IPAddr::Error
    host.match?(/\A[\d.x]+\z/i)
  end

  def self.secret?(text) = Chat::SecretFree::SECRET_PATTERNS.values.any? { |pattern| text.match?(pattern) }

  def self.redacted(text) = Chat::SecretFree::SECRET_PATTERNS.reduce(text) { |kept, (name, pattern)| kept.gsub(pattern, "[REDACTED:#{name}]") }
end
