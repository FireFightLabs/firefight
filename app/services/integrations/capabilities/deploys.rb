module Integrations
  module Capabilities
    # The one shape every provider's deploys are read into, kept as data beside the text recent_deploys answers with. A
    # watch waiting on a new deploy keeps the one live when it began and counts only a newer one, whichever provider runs
    # it. Succeeded means the deploy rolled out and is serving.
    module Deploys
      DEPLOYS = "deploys".freeze
      # A commit is matched by its first characters, as a person names it, never by fewer than this.
      SHORT_COMMIT = 7

      # live is true for the deploy serving now, false for one that no longer is, and nil when the provider does not say.
      Deploy = Data.define(:id, :commit, :branch, :tag, :version, :status, :live, :started_at, :finished_at) do
        def initialize(id: nil, commit: nil, branch: nil, tag: nil, version: nil, status: nil, live: nil, started_at: nil, finished_at: nil)
          super(id: id.presence&.to_s, commit: commit.presence&.to_s&.downcase, branch: branch.presence&.to_s, tag: tag.presence&.to_s,
                version: version.presence&.to_s, status: status, live: live, started_at: RunHistory.time(started_at), finished_at: RunHistory.time(finished_at))
        end

        # Whether it can be told apart from another deploy, by its id, its commit or its version.
        def identified? = [ id, commit, version ].any?(&:present?)

        def finished? = History::FINISHED.include?(status)

        def failed? = [ History::FAILED, History::CANCELLED ].include?(status)

        # Rolled out and serving, as far as the provider says.
        def serving? = status == History::SUCCEEDED && live != false

        # The same deploy, by whichever of its id, commit and version both carry.
        def same?(other)
          return id == other.id if id.present? && other.id.present?
          return Deploys.same_commit?(commit, other.commit) && version == other.version if commit.present? && other.commit.present?

          version.present? && version == other.version
        end

        def commit?(wanted) = Deploys.same_commit?(commit, wanted)

        # What a person calls it, such as cf0bcbe or v42.
        def short = commit&.first(SHORT_COMMIT) || version || tag || id

        def to_h
          { "id" => id, "commit" => commit, "branch" => branch, "tag" => tag, "version" => version, "status" => status, "live" => live,
            "started_at" => started_at&.utc&.iso8601, "finished_at" => finished_at&.utc&.iso8601 }.compact
        end

        def self.from_h(hash)
          hash = hash.to_h.transform_keys(&:to_s)
          new(**members.to_h { |member| [ member, hash[member.to_s] ] })
        end
      end

      module_function

      # The answer with its deploys kept as data, next to whatever data it already holds. A tool that answers in plain
      # text is wrapped as a result first, so the text Halon reads is unchanged.
      def with_deploys(result, deploys)
        result = { "content" => [ { "type" => "text", "text" => result.to_s } ] } unless result.is_a?(Hash)
        result.merge(Telemetry::STRUCTURED => result.fetch(Telemetry::STRUCTURED, {}).merge(DEPLOYS => deploys.map(&:to_h)))
      end

      # The deploys an answer holds, newest first, or nil when it holds none as data, such as an error or a provider that
      # answers in text alone.
      def deploys_of(result)
        return if !result.is_a?(Hash) || result["isError"] == true

        structured = result[Telemetry::STRUCTURED] || result[Telemetry::STRUCTURED.to_sym]
        listed = structured.is_a?(Hash) ? (structured[DEPLOYS] || structured[DEPLOYS.to_sym]) : nil
        return unless listed.is_a?(Array)

        listed.map { |hash| Deploy.from_h(hash) }.sort_by { |deploy| -(deploy.started_at || deploy.finished_at || Time.zone.at(0)).to_f }
      end

      # The deploy the provider marks live, or else the newest that finished rolling out.
      def live(deploys)
        deploys.find { |deploy| deploy.live == true } ||
          deploys.select { |deploy| deploy.status == History::SUCCEEDED && deploy.live.nil? }.max_by { |deploy| (deploy.finished_at || deploy.started_at || Time.zone.at(0)).to_f }
      end

      def same_commit?(one, other)
        one = one.to_s.downcase.strip
        other = other.to_s.downcase.strip
        return false if one.length < SHORT_COMMIT || other.length < SHORT_COMMIT

        one.start_with?(other) || other.start_with?(one)
      end

      # A provider's own word for a deploy's state in Firefight's, by the mapping its pack gives. A word nobody mapped is
      # still going rather than guessed over.
      def status(word, mapping) = History.status(word, mapping)
    end
  end
end
