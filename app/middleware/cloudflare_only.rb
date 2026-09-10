require "ipaddr"
require "net/http"

# CLOUDFLARE_ONLY is "behind_lb" (checks X-Forwarded-For) or "direct" (checks REMOTE_ADDR).
# /up stays open because health checks come from the LB or uptime monitors.
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
    return @app.call(env) if from_cloudflare?(env)

    forbidden
  end

  private

  # The whole X-Forwarded-For chain is scanned because the Hetzner LB does
  # not append the connecting IP.
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
