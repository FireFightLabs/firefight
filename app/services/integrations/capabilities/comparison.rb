module Integrations
  module Capabilities
    # What a range of commits changed, kept as data beside the text a code host's compare_commits answers with, so a
    # deploy can say what it carried, and a rollback what it undoes, without anyone reading every diff. Nothing here knows
    # a code host.
    module Comparison
      COMPARISON = "comparison".freeze
      TITLES_SHOWN = 5
      MIGRATIONS_SHOWN = 5

      # commits is how many there are, titles the first line of each, newest first, kinds how many changed files are of
      # each CodeChange kind and migrations the paths of those that change the database. complete is false when the host
      # listed only part of the range. link is the host's own page for the comparison, when it gave one.
      Range = Data.define(:commits, :titles, :kinds, :migrations, :complete, :link) do
        def initialize(link: nil, **) = super

        def files = kinds.values.sum

        def migrations? = migrations.any?

        def to_h = { "commits" => commits, "titles" => titles, "kinds" => kinds, "migrations" => migrations, "complete" => complete, "link" => link }.compact

        def self.from_h(hash)
          hash = hash.to_h.transform_keys(&:to_s)
          new(commits: hash["commits"].to_i, titles: Array(hash["titles"]).map(&:to_s), kinds: hash["kinds"].to_h.transform_keys(&:to_s).transform_values(&:to_i),
              migrations: Array(hash["migrations"]).map(&:to_s), complete: hash["complete"] != false, link: hash["link"].presence)
        end
      end

      module_function

      # The answer with what it compared kept as data. titles are newest first, paths every changed file.
      def with_comparison(text, commits:, titles:, paths:, complete: true, link: nil)
        kinds = paths.group_by { |path| CodeChange.kind_for(path) }
        range = Range.new(commits: commits, titles: titles.map { |title| title.to_s.lines.first.to_s.strip }.first(TITLES_SHOWN * 4),
                          kinds: CodeChange::KINDS.filter_map { |kind| [ kind, kinds[kind].size ] if kinds[kind] }.to_h,
                          migrations: Array(kinds[CodeChange::KIND_MIGRATION]), complete: complete, link: link.presence)
        { "content" => [ { "type" => "text", "text" => text.to_s } ], Telemetry::STRUCTURED => { COMPARISON => range.to_h } }
      end

      # What an answer compared, or nil when it holds no comparison as data, such as an error.
      def of(result)
        return if !result.is_a?(Hash) || result["isError"] == true

        structured = result[Telemetry::STRUCTURED] || result[Telemetry::STRUCTURED.to_sym]
        kept = structured.is_a?(Hash) ? (structured[COMPARISON] || structured[COMPARISON.to_sym]) : nil
        Range.from_h(kept) if kept.is_a?(Hash)
      end

      # The range in a few lines, with how many commits and files of each kind, the newest commits, the migrations and
      # the host's page for it.
      def described(range)
        kinds = range.kinds.map { |kind, count| "#{CodeChange::KIND_LABELS.fetch(kind, kind).downcase} #{count}" }
        lines = [ "#{range.commits} #{range.commits == 1 ? 'commit' : 'commits'} and #{range.files} changed files" \
                  "#{" (#{kinds.join(', ')})" if kinds.any?}.#{' The code host listed only part of the range, so there is more.' unless range.complete}" ]
        lines << "Newest commits:\n#{shown(range.titles, TITLES_SHOWN, range.commits)}" if range.titles.any?
        lines << "Database migrations:\n#{shown(range.migrations, MIGRATIONS_SHOWN, range.migrations.size)}" if range.migrations?
        lines << range.link if range.link
        lines.join("\n")
      end

      def shown(items, most, total)
        listed = items.first(most).map { |item| "  #{item}" }
        listed << "  and #{total - listed.size} more" if total > listed.size
        listed.join("\n")
      end
    end
  end
end
