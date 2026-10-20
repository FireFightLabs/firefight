module Integrations
  module Packs
    class Github
      # A repository's deployment environments with the rules that hold a deploy (deployments/environments, list
      # environments, Actions read), its deployments read as runs, and running again what made an earlier deployment,
      # which is how a repository rolls back. GitHub keeps no deploy it could repeat by itself. A deployment GitHub Actions
      # made names the run, and the job when there is one, in its status's log_url, and that job runs again on the
      # deployment's commit (actions/jobs/{job_id}/rerun, or actions/runs/{run_id}/rerun for a run alone), Actions write.
      module Deployments
        RUN_PAGE = %r{/actions/runs/(\d+)(?:/job/(\d+))?}
        BRANCH_POLICY = "branch_policy".freeze
        REVIEWERS = "required_reviewers".freeze
        WAIT_TIMER = "wait_timer".freeze
        STATUS_PAGE = 100
        STATUS_PAGES = 10

        def self.included(pack)
          pack.tool :list_environments,
                    summary: "Lists a repository's deployment environments and the rules that hold a deploy to each.",
                    description: "A repository's deployment environments, each with the rules that hold a deploy to it: who must approve it, " \
                                 "a wait timer and which branches may deploy, and its page. Use it to say why a deploy waits",
                    params_schema: Code.object_schema({ "repo" => Code::REPO }, %w[repo]),
                    read_only: true

          pack.tool :redeploy,
                    summary: "Deploys an earlier deployment's commit again by rerunning the job that made it.",
                    description: "Roll back to an earlier deployment by running again the GitHub Actions job that made it, on that " \
                                 "deployment's commit, with the jobs that depend on it. A deployment another system made names no " \
                                 "GitHub Actions run, and that system deploys it again",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO, "deployment" => { "type" => "integer", "description" => "The deployment's id, as recent_deployments shows it" }
                    }, %w[repo deployment]),
                    read_only: false
        end

        def list_environments(environment_row:, arguments:)
          repo = repo_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          asking("list_environments", "GitHub found no repository #{repo}") do
            listed = Array(GithubApp.get("/repos/#{repo}/environments?per_page=100", token: token)["environments"])
            text = if listed.empty?
              "#{repo} has no deployment environments, so nothing holds a deploy."
            else
              "Environments in #{repo}:\n#{listed.map { |environment| environment_line(environment) }.join("\n")}"
            end
            linked(text, repo_page(repo, "deployments"))
          end
        end

        def redeploy(environment_row:, arguments:)
          repo = repo_argument(arguments)
          id = number_argument(arguments, "deployment")
          token = GithubApp.installation_token(environment_row)
          asking("redeploy", "GitHub has no deployment #{id} in #{repo}") do
            deployment = GithubApp.get("/repos/#{repo}/deployments/#{id}", token: token)
            commit = deployment["sha"].to_s[0, 12]
            named = "deployment #{id} of #{commit} to #{deployment['environment']}"
            run_id, job_id = actions_run_of(repo, id, token)
            unless run_id
              fail_policy! "The #{named} names no GitHub Actions run, so another system made it and Firefight cannot run it again. " \
                           "That system deploys #{commit} again."
            end

            # A status's log is only an address its writer gave, so the run must have built this commit, and the job be the run's.
            run = GithubApp.get("/repos/#{repo}/actions/runs/#{run_id}", token: token)
            unless run["head_sha"].to_s.casecmp?(deployment["sha"].to_s)
              fail_policy! "The #{named} names run #{run_id}, which built #{run['head_sha'].to_s[0, 12]} rather than #{commit}, so running it again " \
                           "would not deploy #{commit}. Firefight ran nothing."
            end
            if job_id && GithubApp.get("/repos/#{repo}/actions/jobs/#{job_id}", token: token)["run_id"].to_s != run_id
              fail_policy! "The #{named} names job #{job_id}, which is not part of run #{run_id}, so Firefight ran nothing."
            end
            fail! "Run #{run_id}, which made the #{named}, is still #{run['status']}, so it cannot run again until it finishes." unless run["status"] == Actions::COMPLETED

            what = if job_id
              changing("run job #{job_id} in #{repo} again") { GithubApp.act("/repos/#{repo}/actions/jobs/#{job_id}/rerun", {}, token: token) }
              "the job that made it (job #{job_id}) and the jobs that depend on it"
            else
              changing("run #{repo} run #{run_id} again") { GithubApp.act("/repos/#{repo}/actions/runs/#{run_id}/rerun", {}, token: token) }
              "every job of the run that made it"
            end
            Telemetry.result("Deploying the #{named} again, running #{what} in #{run_name(run, repo)}. If the environment needs an approval, " \
                             "the deploy waits for it. #{Actions::FOLLOW}.", link: actions_link(run["html_url"]))
          end
        end

        private

        # The run, and the job when named, a deployment's statuses say made it. A newer status may leave its log out, so
        # every status is looked through, newest first, a page of 100 at a time until one names a run or none are left.
        def actions_run_of(repo, id, token)
          (1..STATUS_PAGES).each do |page|
            statuses = Array(GithubApp.get("/repos/#{repo}/deployments/#{id}/statuses?#{{ 'page' => page, 'per_page' => STATUS_PAGE }.to_query}", token: token))
            found = statuses.lazy.filter_map { |status| deployment_log(status).to_s.match(RUN_PAGE)&.captures }.first
            return found if found
            return if statuses.size < STATUS_PAGE
          end
          nil
        end

        def environment_line(environment)
          rules = Array(environment["protection_rules"]).filter_map { |rule| rule_words(rule) }
          branches = environment["deployment_branch_policy"].to_h
          if branches["protected_branches"]
            rules << "only protected branches deploy"
          elsif branches["custom_branch_policies"]
            rules << "only the branches its policy names deploy"
          end
          "  #{environment['name']}: #{rules.any? ? rules.join(', ') : 'no rules, any branch deploys at once'}  #{environment['html_url']}"
        end

        def rule_words(rule)
          case rule["type"]
          when REVIEWERS
            "needs approval from #{reviewers_words(rule)}#{', never by whoever started the deploy' if rule['prevent_self_review']}"
          when WAIT_TIMER then "waits #{rule['wait_timer']} minutes before it deploys"
          when BRANCH_POLICY then nil
          else "a #{rule['type'].to_s.tr('_', ' ')} rule"
          end
        end

        # A deployment as a run, named for where it went, so a watch follows it and learns how long one takes.
        def deployment_run(deployment, status)
          deploy = deploy_of(deployment, status)
          said = status.to_h["description"].presence
          Capabilities::History::Run.new(
            id: "#{DEPLOYMENT_RUN}#{deployment['id']}", name: "deployment to #{deployment['environment'].presence || 'an unnamed environment'}",
            status: deploy.status || Capabilities::History.status(nil, DEPLOYMENT_STATUSES), started_at: deploy.started_at, finished_at: deploy.finished_at,
            url: deployment_log(status) || status.to_h["environment_url"].presence,
            detail: "#{deploy.short} by #{deployment.dig('creator', 'login') || 'unknown'}#{", #{Sentence.clean(said)}" if said}"
          )
        end

        # The deployments to the environment named, which GitHub matches whole, else the newest to any environment, so one
        # named in part still matches. Each costs a call for its status, so no more than limit are read.
        def deployment_runs(repo, token, limit, environment = nil)
          listed = ->(query) { Array(GithubApp.get("/repos/#{repo}/deployments?#{query.compact.to_query}", token: token)) }
          deployments = (listed.call("environment" => environment, "per_page" => limit) if environment.present?).presence || listed.call("per_page" => limit)
          deployments.map { |deployment| deployment_run(deployment, newest_status(repo, deployment["id"], token)) }
        end

        def one_deployment(repo, token, given)
          id = Integer(given.to_s.strip, exception: false)
          fail! "run must be a deployment's id as ci_runs gives it, such as #{DEPLOYMENT_RUN}42" unless id&.positive?

          deployment = GithubApp.get("/repos/#{repo}/deployments/#{id}", token: token)
          Capabilities::History.result([ deployment_run(deployment, newest_status(repo, id, token)) ], what: "deployments in #{repo}",
                                       link: actions_link(repo_page(repo, "deployments")))
        end
      end
    end
  end
end
