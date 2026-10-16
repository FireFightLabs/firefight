module Operator
  # Failed platform calls as the console shows them, grouped by workspace, call, the platform's code and channel, and
  # each with its reason read out of the message the platform client recorded, such as "<platform> API error:
  # not_authorized (details: {...})". Warnings are left out, since they never say why a call failed.
  class PlatformFailures
    # The code the platform answered with, a snake_case word after a colon that ends the message or opens its details.
    CODE_PATTERN = /: ([a-z_]+)(?: \(|\z)/
    CODE_SQL = "COALESCE(substring(platform_call_failures.message from ': ([a-z_]+)( \\(|$)'), platform_call_failures.error_class)".freeze
    # An error the platform added, in a details hash that may have been cut short when it was kept.
    ERROR_NOTE = /"\[ERROR\] ((?:[^"\\]|\\.)*)"/
    ERROR_PREFIX = "[ERROR] ".freeze
    OCCURRENCES_LIMIT = 50

    Reason = Data.define(:code, :notes) do
      def line = notes.empty? ? code : "#{code}: #{notes.join(', ')}"
    end

    def self.reason(failure)
      message = failure.message.to_s
      code = message[CODE_PATTERN, 1] || failure.error_class
      Reason.new(code: code, notes: notes_in(message))
    end

    # Grouped in SQL, the latest failure of each group and how many there were, newest group first.
    def self.groups(failures, limit:)
      failures.group(:workspace_id, :operation, Arel.sql(CODE_SQL), :channel_id).order(Arel.sql("MAX(platform_call_failures.created_at) DESC")).limit(limit)
              .pluck(Arel.sql("(ARRAY_AGG(platform_call_failures.id ORDER BY platform_call_failures.created_at DESC))[1]"), Arel.sql("COUNT(*)"))
    end

    # Every kept failure of the same workspace, call, code and channel as this one, newest first.
    def self.alike(failure)
      PlatformCallFailure.where(workspace_id: failure.workspace_id, operation: failure.operation, channel_id: failure.channel_id)
                         .where("#{CODE_SQL} = ?", reason(failure).code)
                         .order(created_at: :desc, id: :desc)
    end

    # The incident whose channel each failure was in, by workspace and channel.
    def self.incidents_for(failures)
      pairs = failures.filter_map { |failure| [ failure.workspace_id, failure.channel_id ] if failure.channel_id }
      return {} if pairs.empty?

      Incident.where(workspace_id: pairs.map(&:first), channel_id: pairs.map(&:last)).index_by { |incident| [ incident.workspace_id, incident.channel_id ] }
    end

    def self.notes_in(message)
      details = message[/\(details: (.*)\)\z/m, 1]
      parsed = details && JSON.parse(details)
      parsed.is_a?(Hash) ? parsed_notes(parsed) : scanned_notes(message)
    rescue JSON::ParserError
      scanned_notes(message)
    end
    private_class_method :notes_in

    def self.parsed_notes(details)
      said = Array(details.dig("response_metadata", "messages")).map(&:to_s).select { |note| note.start_with?(ERROR_PREFIX) }
                                                                .map { |note| note.delete_prefix(ERROR_PREFIX) }
      said << "needs #{details['needed']}" if details["needed"].present?
      said
    end
    private_class_method :parsed_notes

    def self.scanned_notes(message) = message.scan(ERROR_NOTE).flatten.map { |note| note.gsub('\\"', '"') }
    private_class_method :scanned_notes
  end
end
