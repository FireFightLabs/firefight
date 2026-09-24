# Where to look, read from what Firefight already holds: the alerts, what the run was told, the catalog and the incident.
# Nothing here calls a code host or a model. Each clue says where it came from, so a finding can say how it knew.
class Investigation::Clues
  # A stack frame as most languages print it: a source file and a line number.
  FRAME = %r{((?:[\w.\-]+/)*[\w.\-]+\.(?:rb|py|js|jsx|ts|tsx|go|java|kt|php|ex|exs|cs|rs|scala|swift|rake))(?::|", line |\()(\d+)}
  # An exception or failure name, the kind of text that is written in the code that raises it.
  ERROR_NAME = /\b([A-Z][A-Za-z0-9]*(?:Error|Exception|Exhausted|Timeout|Failure|Refused))\b/
  COMMIT = /\A\h{7,40}\z/
  COMMIT_KEYS = /(commit|sha|revision)/i
  RELEASE_KEYS = /(release|version|image[._-]?tag)/i
  NAME_KEYS = /(\A|[._-])(service|app|application|component)(\z|[._-])/i
  REPOSITORY_KEYS = /repo/i
  FIRST_SEEN_KEYS = /(first[._-]?seen|first[._-]?occurrence|started[._-]?at|start[._-]?time)/i
  # Frames in dependencies say where it broke, not whose code broke it.
  VENDORED = %r{(\A|/)(vendor|node_modules|site-packages|dist-packages|gems|\.bundle|go/pkg/mod)/}
  PATH_LIMIT = 10
  ALERT_LIMIT = 10

  def initialize(investigation)
    @investigation = investigation
    @incident = investigation.incident
  end

  def gather
    {
      "started" => started,
      "commits" => unique(alert_clues(COMMIT_KEYS) { |value| value if value.match?(COMMIT) }),
      "releases" => unique(alert_clues(RELEASE_KEYS) { |value| value unless value.match?(COMMIT) }),
      "names" => unique(alert_clues(NAME_KEYS) { |value| value.truncate(80) } + brief_names),
      "repositories" => unique(repository_clues),
      "paths" => unique(path_clues).first(PATH_LIMIT),
      "error_texts" => unique(error_clues)
    }
  end

  private

  def alerts
    @alerts ||= @incident ? @incident.alerts.includes(:alert_source).order(received_at: :asc).first(ALERT_LIMIT) : []
  end

  def brief = @investigation.brief || {}

  def brief_source = "what the run was told (#{brief[Investigation::Brief::KEY_SOURCE] || 'unknown'})"

  # The earliest sign of trouble, since a slow burn often shows small before anyone declares it.
  def started
    candidates = alerts.map { |alert| [ alert.received_at, "alert from #{alert.alert_source.name} received" ] }
    candidates += alert_clues(FIRST_SEEN_KEYS) { |value| parse_time(value) }.map { |clue| [ parse_time(clue["value"]), clue["source"] ] }
    candidates << [ parse_time(brief[Investigation::Brief::KEY_STARTED_AROUND]), brief_source ]
    candidates << [ @incident&.detected_at, "the incident's detected time" ]
    candidates << [ @incident&.declared_at, "the incident's declared time" ]
    # When the run was asked for is a last resort, never a rival to a real sign.
    at, source = candidates.select(&:first).min_by(&:first) || [ @investigation.created_at, "when the run was asked for" ]
    { "at" => at.utc.iso8601, "source" => source, "estimated" => alerts.empty? && brief[Investigation::Brief::KEY_STARTED_AROUND].blank? }
  end

  def alert_clues(keys)
    alerts.flat_map do |alert|
      leaves(alert.fields).filter_map do |key, value|
        next unless key.match?(keys) && value.is_a?(String)

        found = yield(value.strip)
        { "value" => found.is_a?(Time) ? found.iso8601 : found, "source" => "alert from #{alert.alert_source.name}, field #{key}" } if found.present?
      end
    end
  end

  def brief_names
    Array(brief[Investigation::Brief::KEY_NAMES]).map { |name| { "value" => name, "source" => brief_source } }
  end

  def repository_clues
    from_alerts = alert_clues(REPOSITORY_KEYS) { |value| CodeChange.repository_name(value) }
    services = @incident ? @incident.catalog_services : []
    from_catalog = services.filter_map do |service|
      { "value" => service.repository, "source" => "catalog service #{service.name}" } if service.repository
    end
    from_alerts + from_catalog
  end

  def path_clues
    texts = alerts.flat_map { |alert| [ [ alert.title, alert ] ] + leaves(alert.fields).map { |_key, value| [ value, alert ] } }
    texts.flat_map do |text, alert|
      text.to_s.scan(FRAME).filter_map do |path, line|
        next if path.match?(VENDORED)

        { "value" => path.delete_prefix("/"), "line" => line.to_i, "source" => "stack frame in alert from #{alert.alert_source.name}" }
      end
    end
  end

  def error_clues
    from_brief = [ brief[Investigation::Brief::KEY_ERROR_TEXT] ].compact.map { |text| { "value" => text, "source" => brief_source } }
    from_alerts = alerts.flat_map do |alert|
      alert.title.to_s.scan(ERROR_NAME).flatten.map { |name| { "value" => name, "source" => "alert from #{alert.alert_source.name}, title" } }
    end
    from_brief + from_alerts
  end

  # Every key and string value in a nested payload, keys joined the way a provider's docs name them.
  def leaves(value, prefix = nil)
    case value
    when Hash then value.flat_map { |key, inner| leaves(inner, [ prefix, key ].compact.join(".")) }
    when Array then value.flat_map { |inner| leaves(inner, prefix) }
    else [ [ prefix.to_s, value.is_a?(String) ? value : value.to_s ] ]
    end
  end

  def unique(clues)
    clues.uniq { |clue| [ clue["value"], clue["line"] ] }
  end

  def parse_time(value)
    Time.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
end
