# Sentry error reporting for a deployment that asks for it. SENTRY_DSN turns it on for the app and its jobs, and
# SENTRY_FRONTEND_DSN for the browser. Without them the gems are never loaded and the page gets no settings.
# Errors only, since traces go out through OpenTelemetry, so nothing here samples a transaction, profiles or counts sessions.
module ErrorReporting
  # Only these request headers keep their values. Every other header, Authorization, cookies and webhook tokens
  # included, reaches an event as [Filtered].
  HEADERS = %w[Accept Content-Type Content-Length Host User-Agent].freeze

  def self.dsn = ENV["SENTRY_DSN"].presence

  def self.environment = ENV["DEPLOYMENT_ENVIRONMENT"].presence || Rails.env

  # The version the image was built from (SERVICE_VERSION in the Dockerfile). A build without one says dev, which
  # names no release, so none is sent.
  def self.release
    version = ENV["OTEL_SERVICE_VERSION"].presence
    version unless version == "dev"
  end

  # What the browser needs to report its own errors, nil unless the deployment set a frontend DSN.
  def self.browser
    dsn = ENV["SENTRY_FRONTEND_DSN"].presence
    dsn && { dsn:, environment:, release: }
  end

  def self.configure(config)
    config.dsn = dsn
    config.environment = environment
    config.release = release if release
    config.send_default_pii = false
    config.auto_session_tracking = false
    config.propagate_traces = false
    config.hub_isolation_level = :fiber
    config.data_collection.http_headers.request.mode = :allow_list
    config.data_collection.http_headers.request.terms = HEADERS
    config.data_collection.http_headers.response.mode = :off
    config.rails.active_job_propagate_traces = false
    config.before_send = method(:scrub)
  end

  # The request was masked and filtered as it was collected. This holds even for an event that took its request from
  # somewhere else.
  def self.scrub(event, _hint)
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    event.extra = filter.filter(event.extra)
    event.contexts = filter.filter(event.contexts)
    if (request = event.request)
      request.url = masked_url(request.url)
      request.data = filter.filter(request.data) if request.data.is_a?(Hash)
      request.query_string = filter.filter(request.query_string) if request.query_string.is_a?(Hash)
      request.headers = filter.filter(request.headers) if request.headers.is_a?(Hash)
      request.cookies = filter.filter(request.cookies) if request.cookies.is_a?(Hash)
      request.env = filter.filter(request.env) if request.env.is_a?(Hash)
    end
    event
  end

  def self.masked_url(url)
    return url if url.blank?

    origin, path = url.match(%r{\A([a-z][a-z0-9+.-]*://[^/]*)?(.*)\z}im).captures
    "#{origin}#{PathSecret.mask(path)}"
  end
end
