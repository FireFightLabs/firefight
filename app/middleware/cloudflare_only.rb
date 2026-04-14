require "ipaddr"
require "net/http"

# Optional middleware: rejects requests not coming from Cloudflare's edge.
#
# Enabled when CLOUDFLARE_ONLY is set to:
#   - "behind_lb" (default) — app is behind a load balancer with no source
#     IP filtering of its own. Checks the last X-Forwarded-For entry, which
#     is the IP that connected to the LB (should be a Cloudflare edge).
#   - "direct"     — app is exposed to the internet, Cloudflare proxies
#     directly to it. Checks REMOTE_ADDR.
#
# /up is exempt — health checks come from non-Cloudflare sources (LB or
# uptime monitors).
class CloudflareOnly
  HEALTH_CHECK_PATH = "/up".freeze
  IPV4_URL = "https://www.cloudflare.com/ips-v4".freeze
  IPV6_URL = "https://www.cloudflare.com/ips-v6".freeze

  def initialize(app)
    @app = app
    @mode = ENV["CLOUDFLARE_ONLY"]
    @ranges = fetch_cloudflare_ranges if @mode
  end

  def call(env)
    return @app.call(env) unless @mode
    return @app.call(env) if env["PATH_INFO"] == HEALTH_CHECK_PATH

    Rails.logger.info("CloudflareOnly debug: REMOTE_ADDR=#{env['REMOTE_ADDR']} XFF=#{env['HTTP_X_FORWARDED_FOR']} CF=#{env['HTTP_CF_CONNECTING_IP']}")

    edge_ip = source_ip(env)
    return forbidden unless edge_ip
    return @app.call(env) if @ranges.any? { |range| range.include?(edge_ip) }

    forbidden
  rescue IPAddr::InvalidAddressError
    forbidden
  end

  private

  # Returns true if any IP in the X-Forwarded-For chain is a Cloudflare edge.
  # behind_lb mode: scan the whole chain since Hetzner LB doesn't append the
  # connecting IP. The Cloudflare edge appears somewhere in the chain.
  # direct mode: check REMOTE_ADDR.
  def from_cloudflare?(env)
    case @mode
    when "behind_lb"
      forwarded = env["HTTP_X_FORWARDED_FOR"]
      return false unless forwarded
      forwarded.split(",").any? do |raw|
        ip = IPAddr.new(raw.strip)
        @ranges.any? { |range| range.include?(ip) }
      rescue IPAddr::InvalidAddressError
        false
      end
    when "direct"
      ip = IPAddr.new(env["REMOTE_ADDR"])
      @ranges.any? { |range| range.include?(ip) }
    end
  end

  def forbidden
    [ 403, { "Content-Type" => "text/plain" }, [ "Forbidden\n" ] ]
  end

  def fetch_cloudflare_ranges
    [ IPV4_URL, IPV6_URL ].flat_map do |url|
      Net::HTTP.get(URI(url)).split("\n").map { |cidr| IPAddr.new(cidr) }
    end
  rescue => e
    raise "CloudflareOnly: failed to fetch IP list — #{e.message}"
  end
end
