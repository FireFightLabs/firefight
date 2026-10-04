module Integrations
  module Packs
    # What the packs for platforms that run a team's apps share: the time range their tools take, how a limit is read,
    # and how a resource is found by its name or id, so each pack only maps its provider's API.
    module Hosting
      DEFAULT_MINUTES = 60
      MAX_MINUTES = 7 * 24 * 60

      RANGE = {
        "minutes" => { "type" => "integer", "description" => "How far back from now, in minutes (optional, #{DEFAULT_MINUTES})" },
        "start" => { "type" => "string", "description" => "Start of the range as an ISO 8601 time, instead of minutes (optional)" },
        "end" => { "type" => "string", "description" => "End of the range as an ISO 8601 time (optional, now)" }
      }.freeze

      def self.limit(arguments, most) = arguments["limit"].to_i.positive? ? [ arguments["limit"].to_i, most ].min : most

      def self.window(arguments) = Telemetry.range(arguments, default_minutes: DEFAULT_MINUTES, max_minutes: MAX_MINUTES)

      # The row whose id or name is the one asked for, whatever its case, or nil. rows are hashes with :id and :name.
      def self.named(rows, asked)
        wanted = asked.to_s.strip.downcase
        return if wanted.empty?

        rows.find { |row| [ row[:id], row[:name] ].compact.map { |value| value.to_s.downcase }.include?(wanted) }
      end

      # A command a provider reports, such as a start command, with anything that looks like a credential hidden, since a
      # team sometimes writes one inline and no secret reaches the model.
      def self.redacted(text)
        Chat::SecretFree::SECRET_PATTERNS.reduce(text.to_s) { |said, (name, pattern)| said.gsub(pattern, "[REDACTED:#{name}]") }
      end

      # A count per step as a count per minute, so a live reading can be compared with a baseline.
      def self.per_minute(points, step_seconds) = points.map { |at, value| [ at, value * 60.0 / step_seconds ] }
    end
  end
end
