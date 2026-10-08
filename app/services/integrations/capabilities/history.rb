module Integrations
  module Capabilities
    # The one shape every provider's run history is read into: its CI runs, builds or deploys, newest first, each with
    # its status in Firefight's words, when it started and finished, and the link to its page. An adapter reads its
    # provider's answer into Runs and hands them to result, so a watch learns how long a thing usually takes and follows
    # one run the same way whichever provider runs it.
    module History
      QUEUED = "queued".freeze
      RUNNING = "running".freeze
      SUCCEEDED = "succeeded".freeze
      FAILED = "failed".freeze
      CANCELLED = "cancelled".freeze
      STATUSES = [ QUEUED, RUNNING, SUCCEEDED, FAILED, CANCELLED ].freeze
      # Over, one way or another.
      FINISHED = [ SUCCEEDED, FAILED, CANCELLED ].freeze
      # How many finished runs the usual duration is read from at most.
      USUAL_FROM = 10
      LIMIT = 20
      RUNS = "runs".freeze
      USUAL_SECONDS = "usual_seconds".freeze

      # One job or step inside a run, where the provider breaks a run down, so a watch hears the first one that failed
      # while the run still goes. detail says where it failed, such as the step's name. log is how its log is read: the
      # provider's own read tool by its name and the arguments it takes, on the connection that answered.
      Part = Data.define(:id, :name, :status, :started_at, :finished_at, :url, :detail, :log) do
        def initialize(started_at: nil, finished_at: nil, url: nil, detail: nil, log: nil, **) = super

        def failed? = [ FAILED, CANCELLED ].include?(status)

        def seconds
          return unless started_at && finished_at

          (finished_at - started_at).round
        end

        def to_h
          { "id" => id.to_s, "name" => name, "status" => status, "started_at" => started_at&.utc&.iso8601,
            "finished_at" => finished_at&.utc&.iso8601, "url" => url, "detail" => detail, "log" => log }.compact
        end

        def self.from_h(hash)
          log = hash["log"].is_a?(Hash) ? hash["log"].deep_transform_keys(&:to_s) : nil
          new(id: hash["id"], name: hash["name"], status: hash["status"], started_at: Telemetry.parse_time(hash["started_at"]),
              finished_at: Telemetry.parse_time(hash["finished_at"]), url: hash["url"], detail: hash["detail"], log: log)
        end
      end
      # The log reference a part carries: the provider tool's name and its arguments.
      LOG_TOOL = "tool".freeze
      LOG_ARGUMENTS = "arguments".freeze

      # id is the provider's own, number what a person calls it when the provider numbers its runs (#46), name the
      # workflow, pipeline or kind of run (release, build, deploy), detail a short line such as the commit or the job that
      # failed. parts are its jobs or steps, read only when the run was asked for by its id, and nil when not read.
      Run = Data.define(:id, :number, :name, :status, :started_at, :finished_at, :url, :detail, :parts) do
        def initialize(number: nil, name: nil, finished_at: nil, url: nil, detail: nil, parts: nil, **) = super

        # The first job or step that failed, by when it ended.
        def first_failed_part = parts&.select(&:failed?)&.min_by { |part| part.finished_at || Time.current }

        def finished? = FINISHED.include?(status)

        def seconds
          return unless started_at && finished_at

          (finished_at - started_at).round
        end

        # Matches what a person or Halon named it by: its id, its number with or without #, or nothing.
        def named?(reference)
          wanted = reference.to_s.strip.delete_prefix("#")
          wanted.present? && [ id, number ].compact.map(&:to_s).include?(wanted)
        end

        def called?(text) = text.blank? || name.to_s.downcase.include?(text.to_s.downcase.strip)

        def to_h
          {
            "id" => id.to_s, "number" => number&.to_s, "name" => name, "status" => status, "started_at" => started_at&.utc&.iso8601,
            "finished_at" => finished_at&.utc&.iso8601, "seconds" => seconds, "url" => url, "detail" => detail,
            "parts" => parts&.map(&:to_h)
          }.compact
        end

        def self.from_h(hash)
          parts = hash["parts"].is_a?(Array) ? hash["parts"].map { |part| Part.from_h(part.to_h.transform_keys(&:to_s)) } : nil
          new(id: hash["id"], number: hash["number"], name: hash["name"], status: hash["status"],
              started_at: Telemetry.parse_time(hash["started_at"]), finished_at: Telemetry.parse_time(hash["finished_at"]),
              url: hash["url"], detail: hash["detail"], parts: parts)
        end
      end

      module_function

      # The provider's own word for a run's state in Firefight's, by the mapping its adapter gives. A word nobody mapped
      # is still running rather than guessed over.
      def status(word, mapping)
        mapping.fetch(word.to_s.downcase.strip) { RUNNING }
      end

      # How long the runs named text usually take, the middle of the newest finished successes, or nil when none finished.
      def usual_seconds(runs, name: nil)
        took = runs.select { |run| run.status == SUCCEEDED && run.called?(name) && run.seconds&.positive? }.first(USUAL_FROM).map(&:seconds).sort
        return if took.empty?

        middle = took.size / 2
        took.size.odd? ? took[middle] : ((took[middle - 1] + took[middle]) / 2.0).round
      end

      # The capability's answer: a line per run the model reads, and the runs and their usual duration as data, which a
      # watch reads back with runs_of.
      def result(runs, what:, link: nil, name: nil, limit: LIMIT)
        runs = runs.select { |run| run.called?(name) }.sort_by { |run| run.started_at || Time.current }.reverse.first(limit)
        usual = usual_seconds(runs)
        text = if runs.empty?
          "No runs of #{what}#{" named #{name}" if name.present?} were found."
        else
          lines = runs.map { |run| line(run) }
          usually = usual ? " Finished ones usually take #{duration(usual)}." : ""
          "#{runs.size} recent runs of #{what}, newest first.#{usually}\n#{lines.join("\n")}"
        end
        text = "#{text}\n#{Telemetry.link_line(link)}" if link
        { "content" => [ { "type" => "text", "text" => text } ],
          Telemetry::STRUCTURED => { RUNS => runs.map(&:to_h), USUAL_SECONDS => usual } }
      end

      # The runs a history answer holds, or nil when it is not one, such as an error.
      def runs_of(result)
        return if result.nil? || result["isError"] == true

        structured = result[Telemetry::STRUCTURED] || result[Telemetry::STRUCTURED.to_sym]
        listed = structured.is_a?(Hash) ? (structured[RUNS] || structured[RUNS.to_sym]) : nil
        listed && Array(listed).map { |hash| Run.from_h(hash.transform_keys(&:to_s)) }
      end

      def line(run)
        named = [ run.number ? "##{run.number}" : run.id, run.name ].compact.join(" ")
        took = run.seconds ? ", took #{duration(run.seconds)}" : ""
        said = [ "- #{named}: #{run.status}", run.started_at && " started #{run.started_at.utc.iso8601}", took, run.detail && " (#{run.detail})",
                 run.url && " #{run.url}" ]
        [ said.compact.join, *Array(run.parts).map { |part| part_line(part) } ].join("\n")
      end

      def part_line(part)
        took = part.seconds ? ", took #{duration(part.seconds)}" : ""
        "  - #{part.name}: #{part.status}#{took}#{" (#{part.detail})" if part.detail.present?}"
      end

      # A duration as a person says it, such as 18 minutes or 1 hour 5 minutes.
      def duration(seconds)
        return "#{seconds.round} seconds" if seconds < 90

        minutes = (seconds / 60.0).round
        return "#{minutes} minutes" if minutes < 60

        hours, rest = minutes.divmod(60)
        [ "#{hours} #{'hour'.pluralize(hours)}", (rest.positive? ? "#{rest} #{'minute'.pluralize(rest)}" : nil) ].compact.join(" ")
      end
    end
  end
end
