module Integrations
  module Packs
    class Github
      # A workflow run's deployments waiting on an environment's protection rules (actions/get-pending-deployments-for-run,
      # Actions read) and a review of them (actions/review-pending-deployments-for-run, Deployments write). GitHub takes a
      # review only from one of the environment's required reviewers, and says whether the caller is one in
      # current_user_can_approve, so a review the App cannot give is refused before it is sent, naming who can.
      module PendingDeployments
        DECISIONS = { "approve" => "approved", "reject" => "rejected" }.freeze

        def self.included(pack)
          pack.tool :pending_deployments,
                    summary: "Lists the deployments a workflow run is waiting on for approval.",
                    description: "The deployments a GitHub Actions run is waiting on, one per environment held by its protection rules, " \
                                 "with the wait timer, who may review it and whether Firefight's GitHub App may",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO, "run_id" => { "type" => "integer", "description" => "The run's id, as workflow_runs or ci_status shows it" }
                    }, %w[repo run_id]),
                    read_only: true

          pack.tool :review_pending_deployment,
                    summary: "Approves or rejects a deployment waiting on an environment's reviewers.",
                    description: "Approve or reject a GitHub Actions run's deployment waiting on an environment's required reviewers, with a " \
                                 "comment. Approving lets the run's deploy job go on to that environment, rejecting fails it. GitHub " \
                                 "takes this only when Firefight's GitHub App is one of the environment's required reviewers",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO, "run_id" => { "type" => "integer", "description" => "The run's id, as workflow_runs or ci_status shows it" },
                      "environment" => { "type" => "string", "description" => "The waiting environment, such as production, as pending_deployments names it" },
                      "decision" => { "type" => "string", "enum" => DECISIONS.keys, "description" => "approve or reject" },
                      "comment" => { "type" => "string", "description" => "Why, shown with the review on GitHub" }
                    }, %w[repo run_id environment decision comment]),
                    read_only: false
        end

        def pending_deployments(environment_row:, arguments:)
          repo = repo_argument(arguments)
          run = number_argument(arguments, "run_id")
          token = GithubApp.installation_token(environment_row)
          asking("pending_deployments", "GitHub has no run #{run} in #{repo}") do
            pending = Array(GithubApp.get("/repos/#{repo}/actions/runs/#{run}/pending_deployments", token: token))
            text = if pending.empty?
              "Run #{run} in #{repo} is waiting on no environment."
            else
              "Run #{run} in #{repo} is waiting on:\n#{pending.map { |each| pending_line(each) }.join("\n")}"
            end
            linked(text, repo_page(repo, "actions/runs/#{run}"))
          end
        end

        def review_pending_deployment(environment_row:, arguments:)
          repo = repo_argument(arguments)
          run = number_argument(arguments, "run_id")
          name = arguments["environment"].to_s.strip
          fail! "environment is required" if name.empty?
          decision = choice_argument(arguments, "decision", DECISIONS.keys)
          fail! "decision is required, approve or reject" unless decision
          comment = written_text(arguments, "comment")

          token = GithubApp.installation_token(environment_row)
          asking("review_pending_deployment", "GitHub has no run #{run} in #{repo}") do
            pending = Array(GithubApp.get("/repos/#{repo}/actions/runs/#{run}/pending_deployments", token: token))
            waiting = pending.find { |each| each.dig("environment", "name").to_s.casecmp?(name) }
            unless waiting
              fail_policy! "Run #{run} in #{repo} is not waiting on #{name}#{", only on #{pending.map { |each| each.dig('environment', 'name') }.to_sentence}" if pending.any?}."
            end
            unless waiting["current_user_can_approve"]
              fail_policy! "Firefight's GitHub App is not a required reviewer of #{waiting.dig('environment', 'name')}, so GitHub takes a review only from " \
                           "#{reviewers_words(waiting)}. They review it on the run's page."
            end

            GithubApp.write(:post, "/repos/#{repo}/actions/runs/#{run}/pending_deployments",
                            { environment_ids: [ waiting.dig("environment", "id") ], state: DECISIONS.fetch(decision), comment: comment }, token: token)
            linked("#{decision == 'approve' ? 'Approved' : 'Rejected'} the deployment of run #{run} in #{repo} to #{waiting.dig('environment', 'name')}. " \
                   "#{decision == 'approve' ? 'Its deploy job goes on' : 'Its deploy job fails'} once every rule on the environment has its answer.",
                   repo_page(repo, "actions/runs/#{run}"))
          end
        end

        private

        def pending_line(pending)
          timer = pending["wait_timer"].to_i.positive? ? "  wait timer #{pending['wait_timer']} minutes from #{pending['wait_timer_started_at']}" : ""
          "  #{pending.dig('environment', 'name')}  id #{pending.dig('environment', 'id')}#{timer}  reviewers: #{reviewers_words(pending)}  " \
            "Firefight may review: #{pending['current_user_can_approve'] ? 'yes' : 'no'}"
        end

        def reviewers_words(pending)
          names = Array(pending["reviewers"]).filter_map do |reviewer|
            who = reviewer["reviewer"].to_h
            reviewer["type"] == "Team" ? "the #{who['slug'] || who['name']} team" : who["login"]
          end
          names.any? ? names.to_sentence : "nobody named"
        end
      end
    end
  end
end
