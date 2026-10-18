module Integrations
  # How a pull request Halon opened stands, read through the code host that holds it, in one shape whichever host that
  # is. A code host's pack answers pull_request_status(environment_row, repository:, number:, settle:) with a Status, and
  # its event source may answer pull_request_nudges(payload, headers:) with Nudges, so a delivery about a pull request, its
  # checks or its base reaches the pull requests Halon follows at once. Nothing here names a host.
  module PullRequests
    OPEN = "open".freeze
    MERGED = "merged".freeze
    CLOSED = "closed".freeze
    STATES = [ OPEN, MERGED, CLOSED ].freeze

    MERGEABLE = "mergeable".freeze
    CONFLICTED = "conflicted".freeze
    # The host has not worked it out yet, or cannot merge it for another reason it names in blocked.
    UNKNOWN = "unknown".freeze
    BLOCKED = "blocked".freeze

    # What Halon tells the person about and offers to fix.
    PROBLEM_CONFLICT = "conflict".freeze
    PROBLEM_CHECKS = "checks".freeze
    PROBLEM_REVIEW = "changes_requested".freeze
    PROBLEMS = [ PROBLEM_CONFLICT, PROBLEM_CHECKS, PROBLEM_REVIEW ].freeze

    # A check that failed, with its page. A review that asked for changes, with who, what they wrote and its id.
    Check = Data.define(:name, :url)
    Review = Data.define(:id, :reviewer, :body)

    # blocked is the host's own reason a pull request cannot merge when it is not a conflict, such as a draft. checks_pending
    # says some checks have not finished.
    Status = Data.define(:number, :url, :state, :mergeable, :blocked, :head_sha, :base, :base_sha, :failing_checks, :checks_pending, :reviews) do
      def initialize(url: nil, blocked: nil, base_sha: nil, failing_checks: [], checks_pending: false, reviews: [], **) = super

      def open? = state == OPEN

      def problems
        return [] unless open?

        [ (PROBLEM_CONFLICT if mergeable == CONFLICTED), (PROBLEM_CHECKS if failing_checks.any?), (PROBLEM_REVIEW if reviews.any?) ].compact
      end

      # The same problems on the same commits are the same news, so a notice is said once for them. A new commit on the
      # branch, a newly failing check or a new review is new.
      def fingerprint
        parts = problems.map do |problem|
          case problem
          when PROBLEM_CONFLICT then "#{problem}:#{head_sha}"
          when PROBLEM_CHECKS then "#{problem}:#{head_sha}:#{failing_checks.map(&:name).sort.join(',')}"
          else "#{problem}:#{reviews.map(&:id).sort.join(',')}"
          end
        end
        Digest::SHA256.hexdigest(parts.join("|"))
      end

      # Only what the host said, in a sentence or two.
      def words
        name = "PR ##{number}"
        return "#{name} is merged." if state == MERGED
        return "#{name} is closed." if state == CLOSED

        merge = case mergeable
        when MERGEABLE then "The code host says #{name} can merge into #{base}."
        when CONFLICTED then "The code host says #{name} conflicts with #{base}, so it cannot merge."
        when BLOCKED then "The code host says #{name} cannot merge yet: #{blocked}."
        else "The code host has not worked out yet whether #{name} can merge."
        end
        checks = if failing_checks.any? then "Failing #{'check'.pluralize(failing_checks.size)}: #{failing_checks.map(&:name).to_sentence}."
        elsif checks_pending then "Its checks have not all finished yet."
        end
        reviewed = "#{reviews.map(&:reviewer).uniq.to_sentence} asked for changes." if reviews.any?
        [ merge, checks, reviewed ].compact.join(" ")
      end
    end

    # One delivery's news about pull requests in one repository: the numbers it names, and the branches it moved, which
    # reach every pull request whose base or head is one of them.
    Nudge = Data.define(:repository, :numbers, :branches) do
      def initialize(numbers: [], branches: [], **) = super
    end

    # A pull request as one code host connection reads it: the environment row that reaches it, its repository and number.
    Address = Data.define(:environment_row, :repository, :number)

    # What a code host's pack answers so a pull request someone else opened can be checked: which pull request an address
    # is, what it changed, and a comment on it.
    FLAG_HOOKS = %i[pull_request_at pull_request_paths flag_pull_request].freeze

    module_function

    def flags?(integration)
      pack = NativePack.for(integration.provider)
      pack.present? && FLAG_HOOKS.all? { |hook| pack.method_defined?(hook) }
    end

    # The pull request at url as each code host connection of the workspace that owns the address reads it, those whose
    # sweep put its repository on the map first, since one connection may reach repositories another cannot.
    def addressed(workspace, url)
      found = flagging_rows(workspace).filter_map do |row|
        repository, number = NativePack.fetch!(row.integration).pull_request_at(row, url)
        Address.new(environment_row: row, repository: repository, number: number) if repository
      end
      return found if found.size < 2

      held = ResourceMap::Resource.present.where(workspace: workspace, kind: ResourceMap::KIND_REPOSITORY, external_id: found.map(&:repository),
                                                 integration_environment_id: found.map { |address| address.environment_row.id })
                                  .pluck(:integration_environment_id, :external_id)
      found.sort_by { |address| held.include?([ address.environment_row.id, address.repository ]) ? 0 : 1 }
    end

    # Every path the pull request changes, a renamed file under both names.
    def paths(address)
      row = address.environment_row
      NativePack.fetch!(row.integration).pull_request_paths(row, repository: address.repository, number: address.number)
    end

    # A comment on the pull request, written as the connection.
    def flag!(address, body)
      row = address.environment_row
      NativePack.fetch!(row.integration).flag_pull_request(row, repository: address.repository, number: address.number, body: body)
    end

    def flagging_rows(workspace)
      workspace.integrations.active.includes(:integration_environments).select { |integration| integration.holds_code? && flags?(integration) }
               .flat_map { |integration| integration.integration_environments.select(&:enabled).sort_by(&:created_at) }
    end

    def follows?(integration)
      pack = NativePack.for(integration.provider)
      pack.present? && pack.method_defined?(:pull_request_status)
    end

    # settle reads again for a few seconds while the host is still working out whether it can merge, which it does
    # after every push.
    def status(environment_row, repository:, number:, settle: false)
      NativePack.fetch!(environment_row.integration).pull_request_status(environment_row, repository: repository, number: number, settle: settle)
    end

    # What a delivery to a connection says about pull requests, through its provider's event source, or none.
    def nudges(provider_key, payload, headers:)
      source = MapEvents.source_of(provider_key)
      return [] unless source.respond_to?(:pull_request_nudges)

      Array(source.pull_request_nudges(payload, headers: headers))
    rescue StandardError => error
      Rails.logger.warn({ event: "pull_requests.nudges_unread", provider: provider_key, error: error.class.name }.to_json)
      []
    end
  end
end
