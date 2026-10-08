module Integrations
  module Packs
    class Github
      # A repository's branches (repos/list-branches and get-branch, Contents read), the rules on one from its rulesets
      # (repos/get-branch-rules, Metadata read, which every App has) and its classic protection (get-branch-protection,
      # Administration read, read only to add to the answer). A branch Firefight makes is named under halon/ (git/create-ref),
      # and only such a branch is ever deleted (git/delete-ref): never the default branch, a protected one, one a rule
      # keeps from deletion, or one an open pull request still comes from, since deleting it would close that pull request.
      module Branches
        PREFIX = "halon/".freeze
        # Rules from a ruleset that stop a branch being deleted or pushed to directly (repository-rule-deletion, -update and
        # -pull-request in github/rest-api-description).
        DELETE_RULES = %w[deletion].freeze
        PUSH_RULES = %w[update pull_request].freeze
        RULE_WORDS = {
          "creation" => "only some may create it", "update" => "only some may push to it", "deletion" => "it cannot be deleted",
          "required_linear_history" => "its history must stay linear", "merge_queue" => "changes merge through a merge queue",
          "required_deployments" => "deployments must succeed first", "required_signatures" => "commits must be signed",
          "pull_request" => "changes reach it only through a pull request", "required_status_checks" => "checks must pass",
          "non_fast_forward" => "it cannot be force pushed", "code_scanning" => "code scanning must pass", "workflows" => "workflows must pass"
        }.freeze

        def self.included(pack)
          pack.tool :list_branches,
                    description: "A repository's branches, with the commit each one is at and whether it is protected",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO,
                      "protected_only" => { "type" => "boolean", "description" => "Only protected branches (optional)" },
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{Asking::LIST_LIMIT}, at most #{Asking::MAX_LIST})" }
                    }, %w[repo]),
                    read_only: true

          pack.tool :branch_protection,
                    description: "How a branch is protected: the rules from its rulesets and its branch protection, such as required reviews and " \
                                 "checks, whether it can be force pushed or deleted, and who may push to it",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO, "branch" => { "type" => "string", "description" => "The branch (optional, the default branch)" }
                    }, %w[repo]),
                    read_only: true

          pack.tool :create_branch,
                    description: "Make a branch named under #{PREFIX} from a branch, tag or commit, such as for a revert. Only branches made " \
                                 "this way can be deleted with delete_branch",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO,
                      "name" => { "type" => "string", "description" => "The branch's name, which goes under #{PREFIX}, such as revert-pool-size" },
                      "from" => { "type" => "string", "description" => "The branch, tag or commit SHA to start it at (optional, the default branch)" }
                    }, %w[repo name]),
                    read_only: false

          pack.tool :delete_branch,
                    description: "Delete a branch under #{PREFIX}, which Firefight made. Never the default branch, a protected one, or one an " \
                                 "open pull request comes from",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO, "branch" => { "type" => "string", "description" => "The branch, such as #{PREFIX}revert-pool-size" }
                    }, %w[repo branch]),
                    read_only: false
        end

        def list_branches(environment_row:, arguments:)
          repo = repo_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          asking("list_branches", "GitHub found no repository #{repo}") do
            query = { "per_page" => limit_argument(arguments), "protected" => (true if boolean_argument(arguments, "protected_only")) }.compact
            main = default_branch(repo, token)
            branches = Array(GithubApp.get("/repos/#{repo}/branches?#{query.to_query}", token: token))
            lines = branches.map do |branch|
              "  #{branch['name']}  #{branch.dig('commit', 'sha').to_s[0, 12]}#{'  default' if branch['name'] == main}#{'  protected' if branch['protected']}"
            end
            linked(lines.empty? ? "No branches in #{repo} match." : "Branches in #{repo}:\n#{lines.join("\n")}", repo_page(repo, "branches"))
          end
        end

        def branch_protection(environment_row:, arguments:)
          repo = repo_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          asking("branch_protection", "GitHub has no branch #{arguments['branch']} in #{repo}") do
            name = ref_argument(arguments, "branch") || default_branch(repo, token)
            branch = GithubApp.get("/repos/#{repo}/branches/#{Http.segment(name)}", token: token)
            rules = branch_rules(repo, name, token)
            sections = [
              "#{name} in #{repo} is #{branch['protected'] ? 'protected' : 'not protected by branch protection'}, at #{branch.dig('commit', 'sha').to_s[0, 12]}.",
              rules_text(rules),
              (adding("Branch protection settings", "Administration read") { protection_text(repo, name, token) } if branch["protected"])
            ].compact
            linked(sections.join("\n\n"), repo_page(repo, "tree/#{Http.segment(name)}"))
          end
        end

        def create_branch(environment_row:, arguments:)
          repo = repo_argument(arguments)
          given = arguments["name"].to_s.strip.delete_prefix("refs/heads/")
          name = given.start_with?(PREFIX) ? given : "#{PREFIX}#{given}"
          ref_argument({ "name" => name }, "name", required: true)
          fail! "name must name a branch, such as revert-pool-size" if given.delete_prefix(PREFIX).empty? || name.end_with?("/", ".lock") || name.include?("//")

          token = GithubApp.installation_token(environment_row)
          from = ref_argument(arguments, "from")
          asking("create_branch", "GitHub has no #{from ? "branch, tag or commit #{from}" : 'repository'} in #{repo}") do
            start = from || default_branch(repo, token)
            sha = GithubApp.get("/repos/#{repo}/commits/#{Http.segment(start)}", token: token)["sha"]
            GithubApp.write(:post, "/repos/#{repo}/git/refs", { ref: "refs/heads/#{name}", sha: sha }, token: token)
            linked("Made the branch #{name} in #{repo} from #{start} at #{sha.to_s[0, 12]}.", repo_page(repo, "tree/#{name}"))
          end
        rescue GithubApp::Error => error
          raise unless error.message.match?(/answered 422/)

          fail! Sentence.join("GitHub did not make #{name} in #{repo}", error, after: "A branch of that name may already be there, and list_branches shows it")
        end

        def delete_branch(environment_row:, arguments:)
          repo = repo_argument(arguments)
          name = ref_argument(arguments, "branch", required: true).delete_prefix("refs/heads/")
          fail_policy! "Only a branch Firefight made, under #{PREFIX}, is deleted, and #{name} is not one. A person deletes it on GitHub." unless name.start_with?(PREFIX)

          token = GithubApp.installation_token(environment_row)
          asking("delete_branch", "GitHub has no branch #{name} in #{repo}") do
            deletable!(repo, name, token)
            GithubApp.write(:delete, "/repos/#{repo}/git/refs/heads/#{name.split('/').map { |part| Http.segment(part) }.join('/')}", token: token)
            linked("Deleted the branch #{name} in #{repo}.", repo_page(repo, "branches"))
          end
        end

        private

        def deletable!(repo, name, token)
          fail_policy! "#{name} is the default branch of #{repo}, which is never deleted." if name == default_branch(repo, token)

          branch = GithubApp.get("/repos/#{repo}/branches/#{Http.segment(name)}", token: token)
          fail_policy! "#{name} in #{repo} is protected, so it is not deleted." if branch["protected"]

          kept = branch_rules(repo, name, token).select { |rule| DELETE_RULES.include?(rule["type"]) }
          fail_policy! "A ruleset in #{repo} keeps #{name} from being deleted." if kept.any?

          owner = repo.split("/").first
          pulls = Array(GithubApp.get("/repos/#{repo}/pulls?#{{ 'state' => 'open', 'head' => "#{owner}:#{name}", 'per_page' => 10 }.to_query}", token: token))
          return if pulls.empty?

          fail_policy! "#{pulls.map { |pull| "PR ##{pull['number']}" }.to_sentence} still #{pulls.one? ? 'comes' : 'come'} from #{name}, and deleting it would close " \
                "#{pulls.one? ? 'it' : 'them'}. Close #{pulls.one? ? 'it' : 'them'} first if that is what is wanted."
        end

        def branch_rules(repo, name, token)
          Array(GithubApp.get("/repos/#{repo}/rules/branches/#{Http.segment(name)}?per_page=100", token: token))
        end

        def rules_text(rules)
          return "No ruleset applies to it." if rules.empty?

          words = rules.map { |rule| RULE_WORDS.fetch(rule["type"], rule["type"].to_s.tr("_", " ")) }.uniq
          checks = rules.select { |rule| rule["type"] == "required_status_checks" }
                        .flat_map { |rule| Array(rule.dig("parameters", "required_status_checks")).map { |check| check["context"] } }
          reviews = rules.find { |rule| rule["type"] == "pull_request" }&.dig("parameters", "required_approving_review_count")
          [ "Rulesets say: #{words.join(', ')}.", ("Required checks: #{checks.join(', ')}." if checks.any?),
            ("Approving reviews needed: #{reviews}." if reviews.to_i.positive?) ].compact.join(" ")
        end

        def protection_text(repo, name, token)
          protection = GithubApp.get("/repos/#{repo}/branches/#{Http.segment(name)}/protection", token: token)
          reviews = protection["required_pull_request_reviews"]
          checks = protection["required_status_checks"]
          restrictions = protection["restrictions"]
          who = restrictions && [ *Array(restrictions["users"]).map { |user| user["login"] }, *Array(restrictions["teams"]).map { |team| "the #{team['slug']} team" },
                                  *Array(restrictions["apps"]).map { |app| app["name"] } ]
          [
            "Branch protection:",
            ("  Reviews: #{reviews['required_approving_review_count'].to_i} approving#{', from code owners' if reviews['require_code_owner_reviews']}" \
             "#{', stale ones dismissed on a push' if reviews['dismiss_stale_reviews']}" if reviews),
            ("  Checks: #{Array(checks['contexts']).join(', ').presence || 'none named'}#{', and the branch must be up to date' if checks['strict']}" if checks),
            "  Admins #{protection.dig('enforce_admins', 'enabled') ? 'follow these rules too' : 'may skip these rules'}",
            "  Force pushes #{protection.dig('allow_force_pushes', 'enabled') ? 'allowed' : 'blocked'}, deletion #{protection.dig('allow_deletions', 'enabled') ? 'allowed' : 'blocked'}",
            ("  Linear history required" if protection.dig("required_linear_history", "enabled")),
            ("  Locked, read only" if protection.dig("lock_branch", "enabled")),
            ("  Only #{who.to_sentence} may push" if who&.any?)
          ].compact.join("\n")
        end
      end
    end
  end
end
