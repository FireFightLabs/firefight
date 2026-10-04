module Integrations
  module Packs
    # What the packs for platforms that run a team's apps share: how a resource is found by its name or id, and how a
    # count becomes a rate, so each pack only maps its provider's API.
    module Hosting
      # The row whose id or name is the one asked for, whatever its case, or nil. rows are hashes with :id and :name. An id
      # names one row. A name two rows share names neither, so the caller is asked for the id rather than given the first.
      def self.named(rows, asked)
        wanted = asked.to_s.strip.downcase
        return if wanted.empty?

        by_id = rows.find { |row| row[:id].to_s.downcase == wanted }
        return by_id if by_id

        matches = rows.select { |row| row[:name].to_s.downcase == wanted }
        return matches.first unless matches.size > 1

        raise NativePack::Error, "More than one is called #{asked}: #{matches.map { |row| row[:id] }.join(', ')}. Name it by its id."
      end

      # A count per step as a count per minute, so a live reading can be compared with a baseline.
      def self.per_minute(points, step_seconds) = points.map { |at, value| [ at, value * 60.0 / step_seconds ] }
    end
  end
end
