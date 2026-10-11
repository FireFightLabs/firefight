# Some addresses carry their secret as their last path segment: a Logfire alert source's, whose webhook can send no
# header, and the issue tracker and map event addresses, which identify a workspace or connection by a token. The
# segment is swapped for MASK before anything records the path, so request logs, traces, error pages and params never
# hold it, and the secret travels on in the env alone. Routes still match, as the masked segment is still a segment.
class PathSecret
  ENV_KEY = "firefight.path_secret".freeze
  MASK = "[FILTERED]".freeze
  PATTERNS = [
    %r{\A(/api/v1/alerts/[^/]+/)([^/]+)\z},
    %r{\A(/api/v1/(?:issue_events|map_events)/)([^/]+)\z}
  ].freeze
  PATH_KEYS = %w[PATH_INFO REQUEST_PATH REQUEST_URI ORIGINAL_FULLPATH].freeze

  def self.from(request) = request.get_header(ENV_KEY).to_s.presence

  def initialize(app)
    @app = app
  end

  def call(env)
    match = PATTERNS.lazy.filter_map { |pattern| pattern.match(env["PATH_INFO"].to_s) }.first
    if match
      env[ENV_KEY] = match[2]
      masked = "#{match[1]}#{MASK}"
      PATH_KEYS.each { |key| env[key] = env[key].sub(match[0], masked) if env[key].is_a?(String) }
    end
    @app.call(env)
  end
end
