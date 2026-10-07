module Integrations
  module Packs
    class Github
      # The checks and commit statuses on a commit, branch or tag. Check runs come from apps such as GitHub Actions
      # (checks/list-for-ref, Checks read) and statuses from services that post one (repos/get-combined-status-for-ref,
      # Commit statuses read). A required check can be either, so both are read.
      module Checks
        RUNS_SHOWN = 100
        FAILING = %w[failure timed_out cancelled action_required startup_failure].freeze
        STATUS_FAILING = %w[failure error].freeze

        def self.included(pack)
          pack.tool :ref_checks,
                    description: "The checks and commit statuses on a commit, branch or tag, failing ones first, with each one's page. " \
                                 "Read before merging, or to see why a pull request is blocked",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO,
                      "ref" => { "type" => "string", "description" => "A commit SHA, branch or tag (optional, the default branch)" }
                    }, %w[repo]),
                    read_only: true
        end

        Read = Data.define(:text, :sha)

        # Every check run and status on the commit, failing ones first, as lines a person reads.
        def self.lines(repo, ref, token) = read(repo, ref, token).text

        # The same with the commit the ref named, as GitHub said it.
        def self.read(repo, ref, token)
          path = Http.segment(ref)
          runs = Array(GithubApp.get("/repos/#{repo}/commits/#{path}/check-runs?filter=latest&per_page=#{RUNS_SHOWN}", token: token)["check_runs"])
          ordered = runs.partition { |run| FAILING.include?(run["conclusion"]) }.flatten
          run_lines = ordered.map do |run|
            "  #{run['name']}: #{run['conclusion'] || run['status']}#{" (#{run.dig('app', 'name')})" if run.dig('app', 'name')}" \
              "#{", #{run.dig('output', 'title')}" if run.dig('output', 'title').present?}  #{run['html_url'] || run['details_url']}"
          end
          checks = run_lines.any? ? "Checks on #{ref.to_s[0, 40]}:\n#{run_lines.join("\n")}" : "Checks on #{ref.to_s[0, 40]}: none."
          statuses, sha = statuses_text(repo, path, token)
          Read.new(text: [ checks, statuses ].join("\n"), sha: sha || runs.first&.dig("head_sha"))
        end

        def self.statuses_text(repo, path, token)
          combined = GithubApp.get("/repos/#{repo}/commits/#{path}/status?per_page=100", token: token)
          statuses = Array(combined["statuses"])
          return [ "Commit statuses: none.", combined["sha"] ] if statuses.empty?

          ordered = statuses.partition { |status| STATUS_FAILING.include?(status["state"]) }.flatten
          lines = ordered.map { |status| "  #{status['context']}: #{status['state']}#{", #{status['description']}" if status['description'].present?}  #{status['target_url']}".rstrip }
          [ "Commit statuses, #{combined['state']} overall:\n#{lines.join("\n")}", combined["sha"] ]
        rescue GithubApp::NotPermitted
          [ "Commit statuses not shown: Firefight's GitHub App needs Commit statuses read for them.", nil ]
        end
        private_class_method :statuses_text

        def ref_checks(environment_row:, arguments:)
          repo = repo_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          asking("ref_checks", "GitHub has no commit, branch or tag #{arguments['ref']} in #{repo}") do
            ref = ref_argument(arguments) || default_branch(repo, token)
            found = Checks.read(repo, ref, token)
            linked(found.text, found.sha ? repo_page(repo, "commit/#{found.sha}") : repo_page(repo, "commits/#{Http.segment(ref)}"))
          end
        end
      end
    end
  end
end
