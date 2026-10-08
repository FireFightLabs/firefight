module Integrations
  module Packs
    class Northflank < NativePack
      # The query options each call inside the project takes, read from the API reference the docs store writes out from
      # Northflank's own client, so api_request sends a call only the names Northflank reads for it. Before the store is
      # filled nothing is listed, and api_request checks no names.
      module ApiReference
        FOLDER = "api/project/".freeze
        CACHE = 10.minutes
        HEADING = /\A### (?<verb>[A-Z]+) (?<path>\S+)\z/
        QUERY = /\AQuery: (?<names>.+)\.\z/
        PLACEHOLDER = /\A\{[^}]+\}\z/

        Call = Data.define(:verb, :segments, :query) do
          def matches?(verb, wanted)
            self.verb == verb && segments.size == wanted.size &&
              segments.zip(wanted).all? { |segment, part| segment.match?(PLACEHOLDER) || segment == part }
          end

          def placeholders = segments.count { |segment| segment.match?(PLACEHOLDER) }
        end

        # The names the reference lists for the call, which may be none, or nil when it does not list the call. Where a
        # fixed segment and a placeholder would both fit, the fixed one is meant.
        def self.query_names(verb, path)
          wanted = path.split("/")
          calls.select { |call| call.matches?(verb, wanted) }.min_by(&:placeholders)&.query
        end

        def self.calls
          Rails.cache.fetch([ "northflank_api_reference", pages.maximum(:updated_at)&.to_i ], expires_in: CACHE) do
            pages.order(:path).pluck(:content).flat_map { |content| parse(content.lines(chomp: true)) }
          end
        end

        def self.pages = ProviderDocPage.where(provider: PROVIDER_KEY).where("path LIKE ?", "#{FOLDER}%").where.not("path LIKE ?", "#{FOLDER}%/%")

        def self.parse(lines)
          lines.each_with_object([]) do |line, found|
            if (heading = line.match(HEADING))
              found << Call.new(verb: heading[:verb], segments: heading[:path].split("/"), query: [])
            elsif (listed = line.match(QUERY)) && found.any?
              found[-1] = found.last.with(query: listed[:names].split(",").map(&:strip))
            end
          end
        end
      end
    end
  end
end
