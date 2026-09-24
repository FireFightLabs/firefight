# What whoever started a run told it: what is failing, roughly when it began, any names and any error text.
# A chat hands it over from what the person said, a command from the words after it. Every value keeps where it came from.
class Investigation::Brief
  SYMPTOM_LIMIT = 500
  NAME_LIMIT = 10
  TEXT_LIMIT = 300

  KEY_SYMPTOM = "symptom".freeze
  KEY_STARTED_AROUND = "started_around".freeze
  KEY_NAMES = "names".freeze
  KEY_ERROR_TEXT = "error_text".freeze
  KEY_SOURCE = "source".freeze

  # Where the words came from, which the clues repeat so a finding can say how it knew.
  SOURCE_COMMAND = "the investigate command".freeze
  SOURCE_CHAT = "the chat that asked for it".freeze
  SOURCE_MCP = "an outside agent over MCP".freeze
  SOURCE_REHEARSAL = "a bench case".freeze

  # The same fields for the chat's tool and the MCP tool, so an outside agent and Halon hand over the same thing.
  SCHEMA = {
    KEY_SYMPTOM.to_sym => { type: "string", description: "What is failing, in the words of whoever reported it (optional)" },
    KEY_STARTED_AROUND.to_sym => { type: "string", description: "Roughly when it started, as ISO 8601, when someone said so (optional)" },
    KEY_NAMES.to_sym => { type: "array", items: { type: "string" }, description: "Services, apps or repositories mentioned (optional)" },
    KEY_ERROR_TEXT.to_sym => { type: "string", description: "An error message or name as it appeared, e.g. PoolExhausted (optional)" }
  }.freeze

  # Arguments as a tool or a form gives them, into the shape a run stores. A time it cannot read is dropped, not guessed.
  def self.from(arguments, source:)
    arguments = arguments.to_h.stringify_keys
    brief = {
      KEY_SYMPTOM => arguments[KEY_SYMPTOM].to_s.squish.truncate(SYMPTOM_LIMIT).presence,
      KEY_STARTED_AROUND => started_around(arguments[KEY_STARTED_AROUND]),
      KEY_NAMES => Array(arguments[KEY_NAMES]).map { |name| name.to_s.squish }.compact_blank.uniq.first(NAME_LIMIT).presence,
      KEY_ERROR_TEXT => arguments[KEY_ERROR_TEXT].to_s.strip.truncate(TEXT_LIMIT).presence
    }.compact
    brief.empty? ? {} : brief.merge(KEY_SOURCE => source)
  end

  def self.started_around(value)
    Time.iso8601(value.to_s).utc.iso8601 if value.present?
  rescue ArgumentError
    nil
  end
  private_class_method :started_around
end
