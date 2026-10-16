# Some addresses carry their secret as their last path segment, such as an alert source's whose provider can send no
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

  # The path with its secret segment masked, as it is passed on. A path that carries none comes back unchanged.
  def self.mask(path)
    match = match(path)
    match ? path.sub(match[0], "#{match[1]}#{MASK}") : path
  end

  def self.match(path) = PATTERNS.lazy.filter_map { |pattern| pattern.match(path.to_s) }.first

  def initialize(app)
    @app = app
  end

  def call(env)
    match = self.class.match(env["PATH_INFO"])
    if match
      env[ENV_KEY] = match[2]
      masked = "#{match[1]}#{MASK}"
      PATH_KEYS.each { |key| env[key] = env[key].sub(match[0], masked) if env[key].is_a?(String) }
    end
    @app.call(env)
  end
end
