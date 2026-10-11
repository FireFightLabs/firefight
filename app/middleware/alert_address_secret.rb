# A tool whose webhook can carry no header, such as Logfire, posts to its alert source's address with the source's secret
# as one more path segment. The segment is taken out of the request before anything records the path, so request logs,
# traces and error pages see /api/v1/alerts/<endpoint_path> and the secret travels on in the env alone.
class AlertAddressSecret
  ENV_KEY = "firefight.alert_address_secret".freeze
  PATTERN = %r{\A(/api/v1/alerts/[^/]+)/([^/]+)\z}
  PATH_KEYS = %w[PATH_INFO REQUEST_PATH REQUEST_URI ORIGINAL_FULLPATH].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    match = PATTERN.match(env["PATH_INFO"].to_s)
    if match
      with_secret = match[0]
      env[ENV_KEY] = match[2]
      PATH_KEYS.each { |key| env[key] = env[key].sub(with_secret, match[1]) if env[key].is_a?(String) }
    end
    @app.call(env)
  end
end
