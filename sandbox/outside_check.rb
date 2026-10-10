# Checks an address the way someone outside would reach it, from the box's own network: what DNS answers, what an HTTP
# request gets and how long each part of it takes, and the certificate the server presents. Prints one JSON object.
# Standard library and curl only, so it runs in any image that has the terminal.
require "json"
require "open3"
require "openssl"
require "resolv"
require "socket"
require "timeout"
require "uri"

module OutsideCheck
  TIMEOUT = 20
  MAX_REDIRECTS = 5
  USER_AGENT = "Mozilla/5.0 (compatible; FirefightCheck/1.0; +https://firefight.app)".freeze
  RECORD_TYPES = { "A" => Resolv::DNS::Resource::IN::A, "AAAA" => Resolv::DNS::Resource::IN::AAAA, "CNAME" => Resolv::DNS::Resource::IN::CNAME }.freeze
  METHODS = %w[GET HEAD].freeze
  CERTIFICATE_REFUSED = 60

  def self.call(target, method)
    url = address(target)
    host = url.host
    { "target" => target, "url" => url.to_s, "host" => host, "dns" => dns(host), "http" => http(url, method),
      "tls" => (url.scheme == "https" ? tls(host, url.port) : nil) }
  end

  def self.address(target)
    text = target.to_s.strip
    url = URI.parse(text.include?("://") ? text : "https://#{text}")
    raise ArgumentError, "Only http and https addresses can be checked." unless %w[http https].include?(url.scheme)
    raise ArgumentError, "No host in #{text}." if url.host.to_s.empty?

    url
  end

  def self.dns(host)
    started = clock
    records = Resolv::DNS.open do |resolver|
      resolver.timeouts = 5
      RECORD_TYPES.flat_map do |type, klass|
        resolver.getresources(host, klass).map { |found| { "type" => type, "value" => value_of(found), "ttl" => found.ttl } }
      end
    end
    { "records" => records, "ms" => elapsed(started), "error" => (records.empty? ? "No A, AAAA or CNAME record for #{host}." : nil) }
  rescue Resolv::ResolvError, SocketError, Timeout::Error => error
    { "records" => [], "ms" => elapsed(started), "error" => error.message }
  end

  def self.value_of(found)
    found.respond_to?(:address) ? found.address.to_s : found.name.to_s
  end

  # curl's own timings, each from the start of the request, in milliseconds.
  def self.http(url, method)
    argv = [ "curl", "--silent", "--show-error", "--output", "/dev/null", "--location", "--max-redirs", MAX_REDIRECTS.to_s,
             "--max-time", TIMEOUT.to_s, "--user-agent", USER_AGENT, "--write-out", "%{json}", "--request", method ]
    argv << "--head" if method == "HEAD"
    output, errors, _status = Open3.capture3(*argv, "--", url.to_s)
    said = JSON.parse(output.to_s.lines.last.to_s)
    {
      "status" => said["http_code"].to_i.nonzero?, "final_url" => said["url_effective"], "redirects" => said["num_redirects"].to_i,
      "remote_ip" => said["remote_ip"].to_s.empty? ? nil : said["remote_ip"],
      "certificate_trusted" => trusted(url, said),
      "timings_ms" => {
        "dns" => ms(said["time_namelookup"]), "connect" => ms(said["time_connect"]), "tls" => ms(said["time_appconnect"]),
        "first_byte" => ms(said["time_starttransfer"]), "total" => ms(said["time_total"])
      },
      "error" => (said["exitcode"].to_i.zero? ? nil : (said["errormsg"].to_s.empty? ? errors.strip : said["errormsg"]))
    }
  rescue JSON::ParserError
    { "error" => errors.to_s.strip.empty? ? "curl gave no answer." : errors.strip }
  end

  # nil when the request never reached a handshake. curl's exit code 60 is a certificate it could not verify.
  def self.trusted(url, said)
    return nil unless url.scheme == "https"
    return false if said["exitcode"].to_i == CERTIFICATE_REFUSED
    return nil if said["time_appconnect"].to_f.zero?

    said["ssl_verify_result"].to_i.zero?
  end

  # The certificate as the server presents it, read whether or not it is trusted, so an expired one is still described.
  def self.tls(host, port)
    context = OpenSSL::SSL::SSLContext.new
    context.verify_mode = OpenSSL::SSL::VERIFY_NONE
    certificate = Timeout.timeout(TIMEOUT) do
      socket = TCPSocket.new(host, port)
      ssl = OpenSSL::SSL::SSLSocket.new(socket, context)
      ssl.hostname = host
      ssl.connect
      ssl.peer_cert.tap { ssl.close }
    ensure
      socket&.close
    end
    names = Array(certificate.extensions.find { |extension| extension.oid == "subjectAltName" }&.value.to_s.split(",")).map { |name| name.strip.delete_prefix("DNS:") }
    {
      "subject" => certificate.subject.to_s, "issuer" => certificate.issuer.to_s, "not_before" => certificate.not_before.utc.iso8601,
      "not_after" => certificate.not_after.utc.iso8601, "days_left" => ((certificate.not_after - Time.now) / 86_400).floor,
      "names" => names, "matches_host" => OpenSSL::SSL.verify_certificate_identity(certificate, host)
    }
  rescue OpenSSL::SSL::SSLError, SystemCallError, SocketError, Timeout::Error => error
    { "error" => error.message }
  end

  def self.ms(seconds) = (seconds.to_f * 1000).round

  def self.clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def self.elapsed(started) = ((clock - started) * 1000).round
end

if $PROGRAM_NAME == __FILE__
  method = (ARGV[1] || "GET").upcase
  begin
    raise ArgumentError, "Only #{OutsideCheck::METHODS.join(' and ')} checks run from outside, since a check never changes anything." unless OutsideCheck::METHODS.include?(method)

    puts JSON.generate(OutsideCheck.call(ARGV[0], method))
  rescue ArgumentError, URI::InvalidURIError => error
    puts JSON.generate("error" => error.message)
    exit 2
  end
end
