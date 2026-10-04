module Integrations
  module Packs
    # What the packs for platforms that run a team's apps share: how a resource is found by its name or id, how a command
    # they show is redacted, and how a count becomes a rate, so each pack only maps its provider's API.
    module Hosting
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
