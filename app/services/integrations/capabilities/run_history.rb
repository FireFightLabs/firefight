module Integrations
  module Capabilities
    # run_history answered through a pack tool that already lists runs, such as a list of deployments. The tool's answer
    # carries its runs as data beside its text (structured), so the text a person and Halon read of that tool is
    # unchanged, and the capability reads the runs back into History.result rather than parsing words.
    module RunHistory
      LINK = "link".freeze
      PROVIDER = "provider".freeze
      URL = "url".freeze

      module_function

      # The answer with its runs kept as data, next to any charts it already holds.
      def with_runs(result, runs, link: nil)
        kept = { History::RUNS => runs.map(&:to_h), LINK => (link && { PROVIDER => link.provider, URL => link.url }) }.compact
        result.merge(Telemetry::STRUCTURED => result.fetch(Telemetry::STRUCTURED, {}).merge(kept))
      end

      # Reads a tool's answer as run history, what being what the runs are of, such as "the deploys of web". An error, or
      # an answer that carries no runs, is handed on as it came, so it is never read as a history with nothing in it.
      def presenter(what, given)
        lambda do |result|
          runs = History.runs_of(result)
          next result unless runs

          History.result(runs, what: what, link: link_of(result), name: given["name"], limit: Answers.limit(given, History::LIMIT))
        end
      end

      def link_of(result)
        kept = result.dig(Telemetry::STRUCTURED, LINK)
        kept && Telemetry::Link.new(provider: kept[PROVIDER], url: kept[URL])
      end

      # A time from a provider's answer, or nil.
      def time(value)
        return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
        return Time.zone.at(value) if value.is_a?(Numeric)

        Telemetry.parse_time(value)
      end
    end
  end
end
