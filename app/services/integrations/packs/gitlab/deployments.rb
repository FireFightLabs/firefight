module Integrations
  module Packs
    class Gitlab
      # A project's environments with what protects them (doc/api/environments.md and protected_environments.md), its
      # deployments read as runs, and the changes a deploy takes: running again the job that made an earlier deployment,
      # which is GitLab's own rollback (doc/ci/environments, retry or roll back a deployment, through jobs/:job_id/retry),
      # approving or rejecting a deployment blocked on approval (doc/api/deployments.md, approve or reject, Premium), and
      # stopping an environment (doc/api/environments.md, stop). Each needs a token with the api scope.
      module Deployments
        BLOCKED = "blocked".freeze
        DECISIONS = { "approve" => "approved", "reject" => "rejected" }.freeze
        ENVIRONMENT_STATES = %w[available stopping stopped].freeze
        STOPPED = "stopped".freeze

        def self.included(pack)
          repo = pack::REPO_PARAM
          deployment = { "type" => "integer", "description" => "The deployment's id, as recent_deployments shows it" }
          pack.tool :list_environments,
                    summary: "Lists a project's environments with what protects each and where it serves.",
                    description: "A project's environments, each with its state, tier and address, who may deploy to a protected one and how " \
                                 "many approvals a deploy to it needs. Use it to say why a deploy waits",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo,
                      "state" => { "type" => "string", "enum" => ENVIRONMENT_STATES, "description" => "Only environments in this state (optional, every one)" }
                    }, %w[repo]),
                    read_only: true

          pack.tool :redeploy,
                    summary: "Deploys an earlier deployment's commit again by running the job that made it.",
                    description: "Roll back to an earlier deployment by running again the job that made it, on that deployment's commit, " \
                                 "as GitLab's own rollback does",
                    params_schema: CodeHost::Code.object_schema({ "repo" => repo, "deployment" => deployment }, %w[repo deployment]),
                    read_only: false

          pack.tool :approve_deployment,
                    summary: "Approves or rejects a deployment waiting for approval.",
                    description: "Approve or reject a deployment to a protected environment that waits for approval, with a comment. " \
                                 "Approving lets its job go on once every rule has its approvals, rejecting stops it. Needs GitLab Premium " \
                                 "or Ultimate and a token whose user may approve deployments to that environment",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo, "deployment" => deployment,
                      "decision" => { "type" => "string", "enum" => DECISIONS.keys, "description" => "approve or reject" },
                      "comment" => { "type" => "string", "description" => "Why, shown with the approval in GitLab (optional)" },
                      "represented_as" => { "type" => "string", "description" => "The user, group or role to approve as, when the token's user belongs to more than one approval rule (optional)" }
                    }, %w[repo deployment decision]),
                    read_only: false

          pack.tool :stop_environment,
                    summary: "Stops an environment, running its stop job.",
                    description: "Stop an environment, such as a review app no longer needed, which runs the stop job its pipeline defines. " \
                                 "force stops it without running that job",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo,
                      "environment_id" => { "type" => "integer", "description" => "The environment's id, as list_environments shows it" },
                      "force" => { "type" => "boolean", "description" => "Stop it without running its stop job (optional)" }
                    }, %w[repo environment_id]),
                    read_only: false
        end

        def list_environments(environment_row:, arguments:)
          repo = repo_argument(arguments)
          state = arguments["state"].presence
          fail! "state must be one of #{ENVIRONMENT_STATES.join(', ')}" if state && ENVIRONMENT_STATES.exclude?(state)

          gitlab = api(environment_row)
          environments, more = gitlab.list("#{GitlabApi.project(repo)}/environments", { "states" => state }.compact)
          page = link(gitlab.web_url(repo, "-", "environments"))
          return Telemetry.result("#{repo} has no#{" #{state}" if state} environments.", link: page) if environments.empty?

          protections, unread = protections_of(gitlab, repo)
          lines = environments.map { |environment| environment_line(environment, protections[environment["name"]]) }
          lines << "  More environments than these." if more
          lines << unread if unread
          Telemetry.result("Environments in #{repo}:\n#{lines.join("\n")}", link: page)
        end

        def redeploy(environment_row:, arguments:)
          repo = repo_argument(arguments)
          gitlab = api(environment_row)
          deployment = gitlab.get("#{GitlabApi.project(repo)}/deployments/#{positive_id(arguments, 'deployment')}")
          named = "deployment #{deployment['id']} of #{deployment['sha'].to_s[0, 12]} to #{deployment.dig('environment', 'name')}"
          job = deployment["deployable"]
          fail_policy! "The #{named} was not made by a job, so there is no job to run again. Whatever recorded it deploys that commit again." unless job.is_a?(Hash) && job["id"]
          unless Pipelines::JOB_ENDED.include?(job["status"])
            fail! "Job #{job['id']}, which made the #{named}, is still #{job['status']}, so it cannot run again until it finishes."
          end

          retried = changing("run job #{job['id']} in #{repo} again") { gitlab.post("#{GitlabApi.project(repo)}/jobs/#{job['id']}/retry") }
          Telemetry.result("Deploying the #{named} again as job #{retried['id']}, a new run of #{job['stage']}/#{job['name']}. It is " \
                           "#{retried['status'] || 'starting'}. If the environment needs an approval, the deploy waits for it. #{Pipelines::FOLLOW}.",
                           link: link(retried["web_url"] || job["web_url"]))
        end

        def approve_deployment(environment_row:, arguments:)
          repo = repo_argument(arguments)
          decision = arguments["decision"].to_s.strip.downcase
          fail! "decision must be approve or reject" unless DECISIONS.key?(decision)

          gitlab = api(environment_row)
          deployment = gitlab.get("#{GitlabApi.project(repo)}/deployments/#{positive_id(arguments, 'deployment')}")
          named = "deployment #{deployment['id']} of #{deployment['sha'].to_s[0, 12]} to #{deployment.dig('environment', 'name')}"
          fail_policy! "The #{named} is #{deployment['status']}, not waiting for approval, so there is nothing to approve." unless deployment["status"] == BLOCKED

          body = { "status" => DECISIONS.fetch(decision), "comment" => arguments["comment"].to_s.strip.presence,
                   "represented_as" => arguments["represented_as"].to_s.strip.presence }.compact
          answer = changing("#{decision} the #{named}") { gitlab.post("#{GitlabApi.project(repo)}/deployments/#{deployment['id']}/approval", body) }
          Telemetry.result("#{decision == 'approve' ? 'Approved' : 'Rejected'} the #{named}#{" as #{answer['user'].to_h['username']}" if answer.is_a?(Hash) && answer['user']}. " \
                           "#{decision == 'approve' ? 'Its job goes on once every approval rule has its approvals' : 'Its job does not run'}.",
                           link: link(deployment.dig("deployable", "web_url") || gitlab.web_url(repo, "-", "environments")))
        end

        def stop_environment(environment_row:, arguments:)
          repo = repo_argument(arguments)
          force = ActiveModel::Type::Boolean.new.cast(arguments["force"]) || false
          gitlab = api(environment_row)
          environment = gitlab.get("#{GitlabApi.project(repo)}/environments/#{positive_id(arguments, 'environment_id')}")
          fail! "#{environment['name']} in #{repo} is already stopped." if environment["state"] == STOPPED

          stopped = changing("stop #{environment['name']} in #{repo}") do
            gitlab.post("#{GitlabApi.project(repo)}/environments/#{environment['id']}/stop", ({ "force" => true } if force).to_h)
          end
          how = force ? "without running its stop job" : "running its stop job"
          Telemetry.result("Stopping #{environment['name']} in #{repo}, #{how}. It is #{stopped['state'] || 'stopping'}.",
                           link: link(gitlab.web_url(repo, "-", "environments", environment["id"])))
        end

        private

        # Each protected environment by name, and a line saying they could not be read, since only some tiers and roles may.
        def protections_of(gitlab, repo)
          [ Array(gitlab.get("#{GitlabApi.project(repo)}/protected_environments")).index_by { |protection| protection["name"] }, nil ]
        rescue GitlabApi::Refused, GitlabApi::NotFound
          [ {}, "  Which environments are protected could not be read with this token." ]
        end

        def environment_line(environment, protection)
          said = [ environment["state"], ("#{environment['tier']} tier" if environment["tier"].present?) ].compact.join(", ")
          guarded = if protection
            deployers = Array(protection["deploy_access_levels"]).filter_map { |level| level["access_level_description"] }.uniq
            approvals = protection["required_approval_count"].to_i + Array(protection["approval_rules"]).sum { |rule| rule["required_approvals"].to_i }
            [ ("only #{deployers.to_sentence} deploy" if deployers.any?), ("needs #{approvals} #{'approval'.pluralize(approvals)}" if approvals.positive?) ].compact.join(", ").presence
          end
          "  #{environment['name']} (id #{environment['id']}), #{said}#{", #{guarded}" if guarded}#{"  #{environment['external_url']}" if environment['external_url'].present?}"
        end

        # A deployment as a run, named for where it went, so a watch follows it and learns how long one takes.
        def deployment_run(deployment)
          status = Capabilities::Deploys.status(deployment["status"], DEPLOYMENT_STATUSES)
          job = deployment["deployable"].to_h
          waiting = status == Capabilities::History::WAITING ? ", waiting for approval, approve_deployment gives it" : ""
          Capabilities::History::Run.new(
            id: "#{DEPLOYMENT_RUN}#{deployment['id']}", name: "deployment to #{deployment.dig('environment', 'name') || 'an unnamed environment'}",
            status: status, started_at: Telemetry.parse_time(job["started_at"] || deployment["created_at"]),
            finished_at: (Telemetry.parse_time(job["finished_at"] || deployment["updated_at"]) if Capabilities::History::FINISHED.include?(status)),
            url: job["web_url"], detail: "#{deployment['ref']} at #{deployment['sha'].to_s[0, 12]} by #{deployment.dig('user', 'username') || 'unknown'}#{waiting}"
          )
        end

        def deployment_runs(gitlab, repo, limit)
          Array(gitlab.get("#{GitlabApi.project(repo)}/deployments", "order_by" => "id", "sort" => "desc", "per_page" => limit)).map { |deployment| deployment_run(deployment) }
        end

        def one_deployment(gitlab, repo, given)
          id = Integer(given.to_s.strip, exception: false)
          fail! "run must be a deployment's id as ci_runs gives it, such as #{DEPLOYMENT_RUN}42" unless id&.positive?

          Capabilities::History.result([ deployment_run(gitlab.get("#{GitlabApi.project(repo)}/deployments/#{id}")) ], what: "deployments in #{repo}",
                                       link: link(gitlab.web_url(repo, "-", "environments")))
        end
      end
    end
  end
end
