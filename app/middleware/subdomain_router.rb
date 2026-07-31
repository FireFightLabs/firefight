class SubdomainRouter
  HEALTH_CHECK_PATH = "/up"

  # Paths that must be callable from app.firefight.app for the dashboard to work.
  # Includes Rails engine mounts (Active Storage, Action Mailbox), Vite assets,
  # and the dashboard routes themselves.
  #
  # MCP and the OAuth 2.1 provider live here too, not on api.firefight.app: the
  # authorize step signs the user in through the dashboard, and the session
  # cookie is host-only. Discovery documents advertise whichever host served
  # them, so the endpoint and its authorization server have to share one.
  APP_EXACT    = %w[/ /login /logout].freeze
  APP_PREFIXES = %w[/app /auth /rails /vite /invite-code /onboarding /mcp /oauth /.well-known].freeze

  # Slack webhook paths — must ONLY be callable from slack.firefight.app.
  SLACK_EXACT = %w[/api/v1/commands /api/v1/events /api/v1/interactions].freeze

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
      APP_EXACT.include?(path) || APP_PREFIXES.any? { |p| prefix_match?(path, p) }
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
