# One HTTP request a workflow step makes. The address must resolve to a public network, checked as outbound webhooks
# are (Webhooks::SsrfProtector), and the request goes to the address that was checked, so a name that resolves elsewhere
# a moment later is never reached. A connection's credentials ride only to that connection's own hosts, added here and
# never written into the step, and any of them a response echoes is taken out of what is handed back.
class Workflow::HttpCall
  class Refused < StandardError; end

  METHODS = %w[GET HEAD POST PUT PATCH DELETE].freeze
  READS = %w[GET HEAD].freeze
  TIMEOUT = 10.seconds
  RESPONSE_LIMIT = 1.megabyte
  USER_AGENT = "Firefight-Workflows/1.0".freeze
  CLASSES = {
    "GET" => Net::HTTP::Get, "HEAD" => Net::HTTP::Head, "POST" => Net::HTTP::Post, "PUT" => Net::HTTP::Put, "PATCH" => Net::HTTP::Patch,
    "DELETE" => Net::HTTP::Delete
  }.freeze

  Answer = Data.define(:status, :content_type, :body)

  def initialize(workspace)
    @workspace = workspace
  end

  # connection is a connection's slug, whose credentials the request carries.
  def call!(method:, url:, headers: {}, body: nil, connection: nil)
    method = method.to_s.upcase
    raise Refused, "#{method} is not a method it sends. Use #{METHODS.join(', ')}." unless METHODS.include?(method)

    uri = address(url)
    secrets = []
    sent = headers.to_h.transform_keys(&:to_s).merge("User-Agent" => USER_AGENT)
    if connection.present?
      credentials = credentials_for(connection, uri)
      secrets = credentials.values.flat_map { |value| [ value.to_s, value.to_s.split.last ] }
      sent = sent.merge(credentials)
    end
    ip = Webhooks::SsrfProtector.resolve_public_ip(uri.host)
    raise Refused, "#{uri.host} does not resolve to a public address, so nothing was sent." unless ip

    answer = perform(uri, ip, CLASSES.fetch(method), sent, body)
    answer.with(body: scrubbed(answer.body, secrets))
  rescue Resolv::ResolvError, Resolv::ResolvTimeout, SocketError
    raise Refused, "#{uri&.host} could not be found."
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT
    raise Refused, "#{uri&.host} did not answer within #{TIMEOUT.inspect}."
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ECONNRESET, OpenSSL::SSL::SSLError => error
    raise Refused, "#{uri&.host} could not be reached: #{error.message.truncate(200)}"
  end

  # The connection's own hosts: those the registry names for its provider, and the host of the server it was made for.
  def self.hosts_of(integration)
    from_registry = IntegrationProvider.find(integration.provider)&.hosts.to_a
    server = integration.server_url.present? ? URI.parse(integration.server_url).host : nil
    [ *from_registry, server ].compact.map(&:downcase).uniq
  rescue URI::InvalidURIError
    from_registry.to_a
  end

  def self.host_of?(hosts, host) = hosts.any? { |allowed| host == allowed || host.end_with?(".#{allowed}") }

  private

  def address(url)
    uri = URI.parse(url.to_s.strip)
    raise Refused, "#{url} is not an http or https address." unless %w[http https].include?(uri.scheme) && uri.host.present?
    raise Refused, "Leave the user name and password out of the address. Name a connection that holds them instead." if uri.userinfo.present?

    uri
  rescue URI::InvalidURIError
    raise Refused, "#{url} is not an address."
  end

  def credentials_for(slug, uri)
    integration = @workspace.integrations.where(deleted_at: nil).find_by(slug: slug.to_s)
    raise Refused, "No connection here is called #{slug}." unless integration

    hosts = self.class.hosts_of(integration)
    unless self.class.host_of?(hosts, uri.host.downcase)
      raise Refused, "#{integration.display_name}'s credentials go only to its own hosts (#{hosts.join(', ').presence || 'none known'}), and #{uri.host} is not one."
    end

    headers = Integrations::Credentials.headers_for(integration.resolve_environment(nil))
    raise Refused, "#{integration.display_name} keeps no credentials a request can carry." if headers.blank?

    headers
  end

  def perform(uri, ip, request_class, headers, body)
    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = ip
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT
    request = request_class.new(uri, headers)
    request.body = body.is_a?(String) ? body : body.to_json if body.present? && request.request_body_permitted?
    request["Content-Type"] ||= "application/json" if body.present? && !body.is_a?(String)
    received = +""
    response = http.request(request) do |answer|
      answer.read_body do |chunk|
        received << chunk
        raise Refused, "The answer was larger than #{RESPONSE_LIMIT / 1.megabyte} MB, so it was not read." if received.bytesize > RESPONSE_LIMIT
      end
    end
    Answer.new(status: response.code.to_i, content_type: response["Content-Type"].to_s, body: received.force_encoding(Encoding::UTF_8).scrub)
  end

  def scrubbed(text, secrets) = secrets.compact_blank.reduce(text.to_s) { |kept, secret| kept.gsub(secret, "[redacted]") }
end
