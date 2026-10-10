class SubdomainRouter
  HEALTH_CHECK_PATH = "/up"

  # MCP and the OAuth provider live on the app host because authorize signs in through the
  # dashboard with a host-only cookie, and discovery documents advertise the host that served them.
  # A code sandbox reaches its model through /code_agent at APP_HOST, and Halon's terminal the connected tools through /sandbox_relay.
  APP_EXACT    = %w[/ /login /logout].freeze
  APP_PREFIXES = %w[/app /auth /rails /vite /invite-code /onboarding /signup /mcp /oauth /.well-known /operator /code_agent /sandbox_relay].freeze

  SLACK_EXACT = %w[/api/v1/commands /api/v1/events /api/v1/interactions].freeze

  # An engine that serves pages or webhooks on the app host names its own prefix here, so this list never has to.
  def self.allow_on_app_host(prefix)
    extra_app_prefixes << prefix unless extra_app_prefixes.include?(prefix)
  end

  def self.extra_app_prefixes = @extra_app_prefixes ||= []

  def initialize(app)
    @app = app
    @enabled = ENV["SUBDOMAIN_ROUTING"] == "strict"
  end

  def call(env)
    return @app.call(env) unless @enabled
    return @app.call(env) if env["PATH_INFO"] == HEALTH_CHECK_PATH

    subdomain = extract_subdomain(env["HTTP_HOST"])
    path = env["PATH_INFO"]

    return @app.call(env) if allowed?(subdomain, path)

    Rails.logger.info("SubdomainRouter: rejected subdomain=#{subdomain.inspect} path=#{path.inspect}")
    not_found
  end

  private

  def allowed?(subdomain, path)
    case subdomain
    when "app"
      APP_EXACT.include?(path) || (APP_PREFIXES + self.class.extra_app_prefixes).any? { |prefix| prefix_match?(path, prefix) }
    when "api"
      prefix_match?(path, "/api/v1") && !SLACK_EXACT.include?(path)
    when "slack"
      SLACK_EXACT.include?(path)
    end
  end

  def prefix_match?(path, prefix)
    path == prefix || path.start_with?("#{prefix}/")
  end

  def extract_subdomain(host)
    return nil unless host
    hostname = host.split(":").first
    parts = hostname.split(".")
    return nil if parts.length < 3
    parts.first.downcase
  end

  def not_found
    [ 404, { "Content-Type" => "text/plain" }, [ "Not Found\n" ] ]
  end
end
