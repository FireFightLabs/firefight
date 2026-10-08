# Reads providers' documentation from the web for the docs store, the way a polite reader does. It says who it is, waits
# between requests to one host, asks again only for what changed, and on a documentation site keeps to what that site's
# robots.txt allows. GitHub's API and raw files, and npm's registry, are services rather than sites, so their own
# limits apply instead (DocsClient::RateLimited).
class DocsClient
  USER_AGENT = "FirefightDocs/1.0 (+https://firefight.app/docs/ai/provider-documentation)".freeze
  Error = Class.new(StandardError)
  NotFound = Class.new(Error)
  RateLimited = Class.new(Error)
  # A site's robots.txt asks readers like this one to stay off the page, or says its content may not be an AI's input.
  Refused = Class.new(Error)
  # A page too large to be documentation anyone reads, such as a whole API schema written out, which is left out.
  TooLarge = Class.new(Error)

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 30
  MAX_BYTES = 3_000_000
  REDIRECTS = 3
  # The least time between two requests to one host, longer when its robots.txt asks for a Crawl-delay.
  INTERVAL = 0.5
  LONGEST_DELAY = 10.0
  NOT_MODIFIED = 304

  # body is nil when the page did not change since revision, which is the ETag or Last-Modified it answered before.
  Answer = Data.define(:body, :revision, :url)

  def initialize
    @last_request = {}
    @robots = {}
  end

  # A documentation page on a site, read only where the site's robots.txt allows.
  def page(url, revision: nil)
    uri = URI.parse(url)
    robots_for(uri).check!(uri)
    get(uri, revision: revision, delay: robots_for(uri).delay)
  end

  # A file from a service such as GitHub or npm, whose own rate limits apply rather than a robots.txt.
  def file(url, revision: nil, headers: {}) = get(URI.parse(url), revision: revision, headers: headers)

  def json(url, headers: {}) = JSON.parse(file(url, headers: headers.merge("Accept" => "application/json")).body)

  # The raw bytes of a file, such as a package's tarball.
  def download(url) = get(URI.parse(url), binary: true).body

  private

  def get(uri, revision: nil, headers: {}, delay: INTERVAL, binary: false, redirects: REDIRECTS)
    raise Error, "#{uri} is not an https address" unless uri.is_a?(URI::HTTPS)

    wait_for(uri.host, delay)
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT
    headers.each { |name, value| request[name] = value }
    conditional(request, revision)
    response = transport(uri, request)
    answer(uri, response, revision: revision, headers: headers, delay: delay, binary: binary, redirects: redirects)
  rescue Timeout::Error, SystemCallError, SocketError, OpenSSL::SSL::SSLError => error
    raise Error, "could not reach #{uri.host} (#{error.class.name})"
  end

  def transport(uri, request)
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |connection|
      connection.request(request)
    end
  end

  def answer(uri, response, revision:, headers:, delay:, binary:, redirects:)
    code = response.code.to_i
    if response.is_a?(Net::HTTPRedirection) && redirects.positive?
      return get(URI.join(uri.to_s, response["location"].to_s), revision: revision, headers: headers, delay: delay, binary: binary, redirects: redirects - 1)
    end
    return Answer.new(body: nil, revision: revision, url: uri.to_s) if code == NOT_MODIFIED
    raise NotFound, "#{uri} answered #{code}" if code == 404 || code == 410
    raise RateLimited, "#{uri.host} asked to slow down (#{code})" if code == 429 || (code == 403 && response["x-ratelimit-remaining"] == "0")
    raise Error, "#{uri} answered #{code}" unless code.between?(200, 299)

    body = response.body.to_s
    raise TooLarge, "#{uri} is larger than #{MAX_BYTES / 1_000_000} MB" if body.bytesize > MAX_BYTES

    Answer.new(body: binary ? body.b : String.new(body, encoding: Encoding::UTF_8).scrub, revision: response["etag"].presence || response["last-modified"].presence, url: uri.to_s)
  end

  def conditional(request, revision)
    return if revision.blank?

    revision.match?(/\A(W\/)?"/) ? request["If-None-Match"] = revision : request["If-Modified-Since"] = revision
  end

  def wait_for(host, delay)
    last = @last_request[host]
    pause = last && (delay - (monotonic - last))
    sleep(pause) if pause&.positive?
    @last_request[host] = monotonic
  end

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def robots_for(uri)
    @robots[uri.host] ||= begin
      Robots.parse(get(URI.parse("https://#{uri.host}/robots.txt")).body)
    rescue NotFound
      Robots.parse("")
    end
  end

  # The rules of a site's robots.txt that apply to this reader, which are the group naming it or else the one for every reader. The
  # longest matching rule decides, an Allow winning a tie, with * matching anything and $ the end, as RFC 9309 says.
  class Robots
    AGENT = "firefightdocs".freeze
    Rule = Data.define(:allow, :pattern) do
      def length = pattern.length

      def matches?(path) = Regexp.new("\\A#{Regexp.escape(pattern).gsub('\*', '.*').sub(/\\\$\z/, '\z')}").match?(path)
    end

    attr_reader :delay

    def self.parse(text)
      groups = []
      current = nil
      text.to_s.each_line do |line|
        field, value = line.sub(/#.*/, "").split(":", 2).map { |part| part.to_s.strip }
        next if field.blank?

        if field.casecmp?("user-agent")
          current = nil if current && current[:rules].any?
          current ||= { agents: [], rules: [], delay: nil, signals: {} }.tap { |group| groups << group }
          current[:agents] << value.downcase
        elsif current
          read(current, field.downcase, value)
        end
      end
      group = groups.find { |each| each[:agents].include?(AGENT) } || groups.find { |each| each[:agents].include?("*") }
      new(group || { rules: [], delay: nil, signals: {} })
    end

    def self.read(group, field, value)
      case field
      when "allow", "disallow" then group[:rules] << Rule.new(allow: field == "allow", pattern: value) if value.present?
      when "crawl-delay" then group[:delay] = value.to_f
      when "content-signal" then value.split(",").each { |signal| name, said = signal.split("=").map(&:strip); group[:signals][name] = said }
      end
    end

    def initialize(group)
      @rules = group[:rules]
      @delay = [ [ group[:delay].to_f, INTERVAL ].max, LONGEST_DELAY ].min
      @signals = group[:signals]
    end

    def check!(uri)
      raise Refused, "#{uri.host} says its content may not be an AI's input" if @signals["ai-input"] == "no"

      path = uri.request_uri
      rule = @rules.select { |each| each.matches?(path) }.max_by { |each| [ each.length, each.allow ? 1 : 0 ] }
      raise Refused, "#{uri.host}'s robots.txt asks readers to stay off #{uri.path}" if rule && !rule.allow
    end
  end
end
