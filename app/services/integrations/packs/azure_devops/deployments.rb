module Integrations
  module Packs
    class AzureDevops
      # What went out where. A YAML pipeline's deployment job records each deployment on the environment it targets
      # (Environmentdeployment Records - List), and the run that made it says the commit and branch (Builds - List,
      # buildIds). A classic release pipeline keeps its own deployments (Release Deployments - List, on vsrm.dev.azure.com).
      # Reading environments needs Environment (Read & manage), the only environment scope Azure DevOps offers.
      module Deployments
        DEPLOYMENT_LIMIT = 10
        MAX_DEPLOYMENTS = 50
        ENVIRONMENTS_READ = 10
        # A deployment looked up by its id past the first ENVIRONMENTS_READ environments lists them up to this many pages.
        EVERY_ENVIRONMENT_PAGES = 5
        # How many environments past the usual ones a lookup by id reads at most, one request each.
        EVERY_ENVIRONMENT_READS = 100
        ENVIRONMENTS_SHOWN = 5
        CANDIDATES = 30
        NO_DEPLOY_LOOKBACK = 24.hours
        BUILD = "Build".freeze
        # A deployment read as a run carries this before its id, so ci_runs tells it from a pipeline run's.
        DEPLOYMENT_RUN = "deployment-".freeze
        # A classic release deployment is named for redeploy by its release and the release's stage, release/<id>/<id>.
        RELEASE_DEPLOYMENT = %r{\Arelease/(\d+)/(\d+)\z}
        # A release stage already on its way, which is not deployed again on top of itself (EnvironmentStatus).
        RELEASE_GOING = %w[inProgress queued scheduled].freeze
        RELEASE_SUCCEEDED = %w[succeeded partiallySucceeded].freeze
        # A classic release deployment held for a person, an approval or a manual intervention (DeploymentOperationStatus).
        RELEASE_HELD = %w[pending manualinterventionpending].freeze
        # A deployment record's result in Firefight's words (TaskResult). One with no result yet is still going.
        RECORD_STATUSES = {
          "succeeded" => Capabilities::History::SUCCEEDED, "succeededwithissues" => Capabilities::History::SUCCEEDED,
          "failed" => Capabilities::History::FAILED, "canceled" => Capabilities::History::CANCELLED,
          "skipped" => Capabilities::History::CANCELLED, "abandoned" => Capabilities::History::CANCELLED
        }.freeze
        # A classic release deployment's status in Firefight's words (DeploymentStatus).
        RELEASE_STATUSES = {
          "notdeployed" => Capabilities::History::QUEUED, "undefined" => Capabilities::History::QUEUED,
          "inprogress" => Capabilities::History::RUNNING, "succeeded" => Capabilities::History::SUCCEEDED,
          "partiallysucceeded" => Capabilities::History::SUCCEEDED, "failed" => Capabilities::History::FAILED
        }.freeze

        def self.included(pack)
          repo = pack::REPO_PARAM
          pack.tool :recent_deployments,
                    summary: "Lists the recent deployments of a repository or pipeline to its environments.",
                    description: "List what a repository's or pipeline's runs deployed to the project's environments, newest first, each " \
                                 "with the environment, the commit and branch deployed, the outcome, the stage and job and the run that made it",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo.merge("description" => "#{repo['description']}. Or name a pipeline instead (optional)"),
                      "pipeline" => Pipelines::PIPELINE_PARAM.merge("description" => "#{Pipelines::PIPELINE_PARAM['description']}. Or name a repository instead (optional)"),
                      "deployment_environment" => { "type" => "string", "description" => "Only this environment, by name, e.g. production (optional)" },
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{DEPLOYMENT_LIMIT}, at most #{MAX_DEPLOYMENTS})" }
                    }, []),
                    read_only: true

          pack.tool :running_commit,
                    summary: "Finds which commit was running at a given time.",
                    description: "Which commit was running at a given time: the last deployment that succeeded before it, and the one before " \
                                 "that to compare against. Without a deployment it falls back to the default branch at that time and says " \
                                 "so, since a merge is not proof of a deploy",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo,
                      "at" => { "type" => "string", "description" => "The time, as ISO 8601, usually when the incident started" },
                      "deployment_environment" => { "type" => "string", "description" => "The environment, e.g. production (optional, production when there is one)" }
                    }, %w[repo at]),
                    read_only: true

          pack.tool :redeploy,
                    summary: "Deploys an earlier deployment again by rerunning the stage that made it.",
                    description: "Roll back to an earlier deployment by rerunning the stage that deployed it, in the run that made it, every job " \
                                 "of that stage on that run's commit, as Azure DevOps documents for a rollback in a YAML pipeline. A classic " \
                                 "release deployment, named release/<release>/<stage> as release_deployments shows it, is deployed again to " \
                                 "its stage. Approvals and checks on the stage or its environment still wait for a person",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo.merge("description" => "#{repo['description']}. Or name a pipeline instead (optional)"),
                      "pipeline" => Pipelines::PIPELINE_PARAM.merge("description" => "#{Pipelines::PIPELINE_PARAM['description']}. Or name a repository instead (optional)"),
                      "project" => Pipelines::PROJECT_PARAM.merge("description" => "The project, for a classic release deployment named without a repository or pipeline (optional)"),
                      "deployment_environment" => { "type" => "string", "description" => "The environment the deployment went to, by name, e.g. production, as recent_deployments was asked for it (optional)" },
                      "deployment" => { "type" => "string", "description" => "The deployment's id, as recent_deployments or release_deployments shows it" }
                    }, %w[deployment]),
                    read_only: false

          pack.tool :release_deployments,
                    summary: "Lists the deployments of a project's classic release pipelines.",
                    description: "List the deployments of a project's classic release pipelines, newest first, each with the release, the " \
                                 "stage it deployed to, the outcome, who asked for it and its page",
                    params_schema: CodeHost::Code.object_schema({
                      "project" => Pipelines::PROJECT_PARAM,
                      "definition_id" => { "type" => "integer", "description" => "Only this release pipeline, by its id (optional)" },
                      "deployment_environment" => { "type" => "string", "description" => "Only this stage, by name, e.g. production (optional)" },
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{DEPLOYMENT_LIMIT}, at most #{MAX_DEPLOYMENTS})" }
                    }, %w[project]),
                    read_only: true
        end

        def recent_deployments(environment_row:, arguments:)
          azure = api(environment_row)
          target = ci_target(azure, arguments)
          limit = whole_number_argument(arguments, "limit", DEPLOYMENT_LIMIT, MAX_DEPLOYMENTS)
          deployments = deployments_of(azure, target, arguments["deployment_environment"].to_s.strip.presence).first(limit)
          if deployments.empty?
            return Capabilities::Deploys.with_deploys("No deployments recorded for #{target.what}#{" in #{arguments['deployment_environment']}" if arguments['deployment_environment'].present?}.", [])
          end

          # Each is kept as a deploy and as a run, so a watch follows one as it follows a pipeline run.
          result = Capabilities::Deploys.with_deploys(deployments.map { |deployment| deployment_line(deployment) }.join("\n"), deployments.map { |deployment| deploy_of(deployment) })
          Capabilities::RunHistory.with_runs(result, deployments.map { |deployment| deployment_run(deployment) })
        end

        def running_commit(environment_row:, arguments:)
          azure = api(environment_row)
          target = ci_target(azure, arguments.slice("repo"))
          at = time_argument(arguments, "at")
          environment = arguments["deployment_environment"].to_s.strip.presence
          succeeded = deployments_of(azure, target, environment).select do |deployment|
            finished = Telemetry.parse_time(deployment[:record]["finishTime"])
            deployment[:status] == Capabilities::History::SUCCEEDED && deployment[:commit].present? && finished && finished <= at
          end
          deployed = scoped_to_environment(succeeded, environment.to_s).first(2)
          return deployed_text(target.what, at, *deployed) if deployed.any?

          default_branch_text(azure, target, at)
        end

        def release_deployments(environment_row:, arguments:)
          azure = api(environment_row)
          project = project_argument(arguments)
          limit = whole_number_argument(arguments, "limit", DEPLOYMENT_LIMIT, MAX_DEPLOYMENTS)
          query = { "$top" => limit, "queryOrder" => "descending", "definitionId" => (positive_id(arguments, "definition_id") if arguments["definition_id"].present?) }
          wanted = arguments["deployment_environment"].to_s.strip.presence
          found = begin
            azure.values(azure.get("#{AzureDevopsApi.project(project)}/_apis/release/deployments", query.compact))
          rescue AzureDevopsApi::Refused => error
            fail! Sentence.join("Azure DevOps refused to list #{project}'s release deployments", error, after: "Reading them needs Release (Read)")
          rescue AzureDevopsApi::NotFound => error
            fail! Sentence.join("Azure DevOps found no classic releases for #{project}", error, after: "Check the project's name and that it uses classic release pipelines")
          end
          found = found.select { |deployment| deployment.dig("releaseEnvironment", "name").to_s.casecmp?(wanted) } if wanted
          page = link(project_page(azure, project))
          return Capabilities::Deploys.with_deploys("No classic release deployments in #{project}#{" to #{wanted}" if wanted}.", []) if found.empty?

          text = found.map do |deployment|
            "#{release_deployment_id(deployment)}  #{deployment['startedOn'] || deployment['queuedOn']}  #{deployment.dig('releaseDefinition', 'name')}  " \
              "#{deployment.dig('release', 'name')}  #{deployment.dig('releaseEnvironment', 'name')}  #{release_word(deployment)}  " \
              "by #{deployment.dig('requestedFor', 'displayName') || 'unknown'}  #{deployment.dig('release', '_links', 'web', 'href')}"
          end.join("\n")
          deploys = found.map do |deployment|
            status = release_status(deployment)
            Capabilities::Deploys::Deploy.new(id: release_deployment_id(deployment), version: deployment.dig("release", "name"), status: status,
                                              started_at: deployment["startedOn"], environment: deployment.dig("releaseEnvironment", "name"),
                                              finished_at: (deployment["completedOn"] if Capabilities::History::FINISHED.include?(status)))
          end
          Capabilities::Deploys.with_deploys([ text, (Telemetry.link_line(page) if page) ].compact.join("\n"), deploys)
        end

        def redeploy(environment_row:, arguments:)
          azure = api(environment_row)
          given = arguments["deployment"].to_s.strip
          if (release = given.match(RELEASE_DEPLOYMENT))
            project = arguments["project"].present? ? project_argument(arguments) : ci_target(azure, arguments).project
            return redeploy_release(azure, project, release[1], release[2])
          end

          id = Integer(given, exception: false)
          fail! "deployment must be a deployment's id as recent_deployments shows it, or release/<release>/<stage> as release_deployments does" unless id&.positive?

          target = ci_target(azure, arguments)
          deployment = deployment_by_id(azure, target, id, arguments["deployment_environment"].to_s.strip.presence)
          fail! "No deployment #{id} among the recent deployments of #{target.what}. recent_deployments lists them." unless deployment

          redeploy_stage(azure, target, deployment)
        end

        private

        # A YAML pipeline's deployment rolled back by rerunning its stage in the run that made it (Stages - Update, state
        # retry with every job), the rollback Azure DevOps' Sprint 235 notes describe. Only a deployment that succeeded is
        # a version to go back to.
        def redeploy_stage(azure, target, deployment)
          record = deployment[:record]
          build = deployment[:build]
          named = "deployment #{record['id']} of #{deployment[:commit].to_s[0, 12].presence || 'an unknown commit'} to #{deployment[:environment]}"
          fail_policy! "The #{named} did not succeed, so it is no version to go back to." unless deployment[:status] == Capabilities::History::SUCCEEDED
          fail_policy! "The run that made the #{named} is no longer kept, so its stage cannot run again." unless build
          fail! "Run #{build['id']}, which made the #{named}, is still #{run_word(build)}, so its stage cannot run again until it finishes." unless build["status"] == COMPLETED

          stage = timeline(azure, target.project, build["id"]).values.find do |each|
            each["type"] == Pipelines::STAGE && [ each["identifier"], each["name"] ].compact.any? { |name| name.to_s.casecmp?(record["stageName"].to_s) }
          end
          fail_policy! "Run #{build['buildNumber']} no longer shows the stage #{record['stageName']} that made the #{named}, so it cannot run again." unless stage

          changing("rerun stage #{stage['name']} of run #{build['id']} in #{target.project}") do
            azure.patch("#{AzureDevopsApi.project(target.project)}/_apis/build/builds/#{build['id']}/stages/#{Http.segment(stage['identifier'] || stage['name'])}",
                        { "state" => "retry", "forceRetryAllJobs" => true })
          end
          Telemetry.result("Deploying the #{named} again by rerunning stage #{stage['name']} of run #{build['buildNumber']} (#{build['id']}) of " \
                           "#{build.dig('definition', 'name')}, on #{branch_name(build['sourceBranch'])} at #{build['sourceVersion'].to_s[0, 12]}, every job of " \
                           "that stage. If the stage or its environment needs an approval, it waits for one. #{Pipelines::FOLLOW}.",
                           link: link(build.dig("_links", "web", "href")))
        end

        # A classic release deployed again to the same stage (Releases - Update Release Environment, status inProgress), only
        # one that succeeded there and is not on its way already.
        def redeploy_release(azure, project, release_id, environment_id)
          path = "#{AzureDevopsApi.project(project)}/_apis/release/releases/#{release_id}/environments/#{environment_id}"
          stage = begin
            azure.get(path)
          rescue AzureDevopsApi::NotFound
            fail! "#{project} has no release #{release_id} with a stage #{environment_id}. release_deployments lists them."
          end
          named = "#{stage.dig('release', 'name') || "release #{release_id}"} to #{stage['name']}"
          fail! "#{named} is #{stage['status']} already, so it is not deployed again on top of itself." if RELEASE_GOING.include?(stage["status"])
          fail_policy! "#{named} did not succeed when it was deployed, so it is no version to go back to." unless RELEASE_SUCCEEDED.include?(stage["status"])

          changing("deploy #{named} again in #{project}") { azure.patch(path, { "status" => "inProgress", "comment" => "Deployed again as a rollback." }) }
          Telemetry.result("Deploying #{named} again in #{project}. If the stage needs an approval or its gates must pass, it waits for them. " \
                           "release_deployments with this project follows it.", link: link(stage.dig("release", "_links", "web", "href")))
        end

        # The deployments the project's environments recorded, newest first, kept to the repository's or pipeline's runs,
        # each with the run that made it. An environment named is read alone.
        def deployments_of(azure, target, environment)
          project = AzureDevopsApi.project(target.project)
          environments = azure.values(azure.get("#{project}/_apis/distributedtask/environments", { "name" => environment, "$top" => ENVIRONMENTS_READ * 5 }.compact))
          environments = environment ? environments.select { |each| each["name"].to_s.casecmp?(environment) } : usual_environments(environments)
          records = environments.flat_map do |each|
            azure.values(azure.get("#{project}/_apis/distributedtask/environments/#{each['id']}/environmentdeploymentrecords", "top" => CANDIDATES))
                 .map { |record| record.merge("environmentName" => each["name"]) }
          end
          records = records.select { |record| record["planType"].to_s.casecmp?(BUILD) }
          runs = runs_by_id(azure, target.project, records.filter_map { |record| record.dig("owner", "id") }.uniq)
          records.filter_map { |record| deployment_of(record, runs[record.dig("owner", "id")], target) }
                 .sort_by { |deployment| deployment[:record]["startTime"] || deployment[:record]["queueTime"] || "" }.reverse
        rescue AzureDevopsApi::Refused => error
          fail! Sentence.join("Azure DevOps refused to read #{target.project}'s environments", error, after: "Reading them needs Environment (Read & manage)")
        end

        # A deployment by its id, in the environment named, else among the usual environments, else among every one, since
        # recent_deployments given one environment lists deployments the usual read does not reach.
        def deployment_by_id(azure, target, id, environment)
          matches = ->(deployments) { deployments.find { |deployment| deployment[:record]["id"] == id } }
          return matches.call(deployments_of(azure, target, environment)) if environment

          matches.call(deployments_of(azure, target, nil)) || deployment_anywhere(azure, target, id)
        end

        # The environments past the usual ones, each one's newest deployments read in turn until one holds the deployment,
        # whose run is read only then, and at most EVERY_ENVIRONMENT_READS of them. A project with more environments than
        # that, or than were listed, is refused with what to name instead.
        def deployment_anywhere(azure, target, id)
          project = AzureDevopsApi.project(target.project)
          environments, more = azure.list("#{project}/_apis/distributedtask/environments", { "$top" => AzureDevopsApi::PAGE_SIZE }, pages: EVERY_ENVIRONMENT_PAGES)
          read = usual_environments(environments).map { |environment| environment["id"] }
          rest = environments.reject { |environment| read.include?(environment["id"]) }
          more ||= rest.size > EVERY_ENVIRONMENT_READS
          rest.first(EVERY_ENVIRONMENT_READS).each do |environment|
            record = azure.values(azure.get("#{project}/_apis/distributedtask/environments/#{environment['id']}/environmentdeploymentrecords", "top" => CANDIDATES))
                          .find { |each| each["id"] == id && each["planType"].to_s.casecmp?(BUILD) }
            next unless record

            build = builds(azure, target.project, "buildIds" => record.dig("owner", "id").to_s).first
            return deployment_of(record.merge("environmentName" => environment["name"]), build, target)
          end
          return unless more

          fail! "#{target.project} has more environments than are searched at once (#{EVERY_ENVIRONMENT_READS} past the usual #{ENVIRONMENTS_READ}), and none " \
                "searched holds deployment #{id}. Name the one it went to with deployment_environment."
        rescue AzureDevopsApi::Refused => error
          fail! Sentence.join("Azure DevOps refused to read #{target.project}'s environments", error, after: "Reading them needs Environment (Read & manage)")
        end

        # The environments a read without a name takes, production-like ones first, from the first page it lists.
        def usual_environments(environments)
          environments.first(ENVIRONMENTS_READ * 5).sort_by { |each| each["name"].to_s.match?(CodeHost::PRODUCTION) ? 0 : 1 }.first(ENVIRONMENTS_READ)
        end

        def runs_by_id(azure, project, ids)
          ids.each_slice(Pipelines::MAX_RUNS).flat_map { |slice| builds(azure, project, "buildIds" => slice.join(",")) }.index_by { |build| build["id"] }
        end

        def deployment_of(record, build, target)
          return if target.definition_id && record.dig("definition", "id") != target.definition_id
          return if target.repository_id && build&.dig("repository", "id") != target.repository_id

          status = record["result"].present? ? Capabilities::Deploys.status(record["result"], RECORD_STATUSES) : Capabilities::History::RUNNING
          { record: record, build: build, status: status, commit: build&.dig("sourceVersion"), branch: branch_name(build&.dig("sourceBranch")),
            environment: record["environmentName"] }
        end

        def deployment_line(deployment)
          record = deployment[:record]
          build = deployment[:build].to_h
          "deployment #{record['id']}  #{record['startTime'] || record['queueTime']}  #{deployment[:environment]}  #{deployment[:branch]}  #{deployment[:commit].to_s[0, 12]}  " \
            "#{record['result'] || 'running'}  #{[ record['stageName'], record['jobName'] ].compact.join(' / ')}  by #{build.dig('requestedFor', 'displayName') || 'unknown'}  " \
            "run #{record.dig('owner', 'name')} (#{record.dig('owner', 'id')}) of #{record.dig('definition', 'name')}#{"  #{build.dig('_links', 'web', 'href')}" if build.dig('_links', 'web', 'href')}"
        end

        # Azure DevOps does not say which deployment serves now, so the newest that finished stands for it.
        def deploy_of(deployment)
          record = deployment[:record]
          finished = record["finishTime"] if Capabilities::History::FINISHED.include?(deployment[:status])
          Capabilities::Deploys::Deploy.new(id: record["id"], commit: deployment[:commit], branch: deployment[:branch], version: record.dig("owner", "name"),
                                            status: deployment[:status], started_at: record["startTime"] || record["queueTime"], finished_at: finished,
                                            environment: deployment[:environment])
        end

        # A deployment as a run, named for where it went, so a watch follows it and learns how long one takes.
        def deployment_run(deployment)
          record = deployment[:record]
          deploy = deploy_of(deployment)
          Capabilities::History::Run.new(
            id: "#{DEPLOYMENT_RUN}#{record['id']}", name: "deployment to #{deployment[:environment].presence || 'an unnamed environment'}",
            status: deploy.status, started_at: Telemetry.parse_time(deploy.started_at), finished_at: Telemetry.parse_time(deploy.finished_at),
            url: deployment[:build]&.dig("_links", "web", "href"),
            detail: "run #{record.dig('owner', 'name')} of #{record.dig('definition', 'name')} by #{deployment[:build]&.dig('requestedFor', 'displayName') || 'unknown'}"
          )
        end

        def deployment_runs(azure, target) = deployments_of(azure, target, nil).map { |deployment| deployment_run(deployment) }

        def one_deployment(azure, target, given)
          id = Integer(given.to_s, exception: false)
          fail! "run must be a deployment's id as ci_runs gives it, such as #{DEPLOYMENT_RUN}41" unless id&.positive?

          found = deployment_by_id(azure, target, id, nil)
          fail! "No deployment #{id} among the recent deployments of #{target.what}. ci_runs with an environment's name lists them." unless found

          Capabilities::History.result([ deployment_run(found) ], what: "deployments of #{target.what}")
        end

        # The id redeploy takes for a classic release deployment, its release and the release's stage.
        def release_deployment_id(deployment) = "release/#{deployment.dig('release', 'id')}/#{deployment.dig('releaseEnvironment', 'id')}"

        # A deployment not finished whose operation waits for an approval or a manual intervention is held for a person.
        def release_held?(deployment)
          !Capabilities::History::FINISHED.include?(Capabilities::Deploys.status(deployment["deploymentStatus"], RELEASE_STATUSES)) &&
            RELEASE_HELD.include?(deployment["operationStatus"].to_s.downcase)
        end

        def release_status(deployment)
          release_held?(deployment) ? Capabilities::History::WAITING : Capabilities::Deploys.status(deployment["deploymentStatus"], RELEASE_STATUSES)
        end

        def release_word(deployment) = release_held?(deployment) ? "#{deployment['deploymentStatus']}, #{Pipelines::HELD_WORDS}" : deployment["deploymentStatus"].to_s

        # An environment asked for by name, else anything that looks like production, else every environment.
        def scoped_to_environment(deployments, environment)
          return deployments.select { |deployment| deployment[:environment].to_s.casecmp?(environment) } if environment.present?

          production = deployments.select { |deployment| deployment[:environment].to_s.match?(CodeHost::PRODUCTION) }
          production.presence || deployments
        end

        def deployed_text(what, at, running, previous = nil)
          record = running[:record]
          lines = [
            "Running in #{what} at #{at.iso8601}: #{running[:commit]}",
            "Source: a deployment. #{running[:environment]} deployment #{record['id']} succeeded #{record['finishTime']} in run " \
            "#{record.dig('owner', 'name')} (#{record.dig('owner', 'id')}), branch #{running[:branch]}."
          ]
          if previous
            lines << "Deployed before it: #{previous[:commit]}, succeeded #{previous[:record]['finishTime']}."
            lines << "What this deployment changed: compare_commits with base #{previous[:commit]} and head #{running[:commit]}."
          else
            lines << "No earlier successful deployment is recorded, so there is nothing to compare this deployment against."
          end
          lines.join("\n")
        end

        def default_branch_text(azure, target, at)
          branch = target.branch
          fail! "#{target.what} has no default branch, so no commit can be named." if branch.blank?

          head = commit_on_branch_at(azure, target.what, branch, at)
          fail! "No commit on #{branch} before #{at.iso8601}." unless head

          base = commit_on_branch_at(azure, target.what, branch, at - NO_DEPLOY_LOOKBACK)
          lines = [
            "Running in #{target.what} at #{at.iso8601}: not known. There is no successful deployment before then.",
            "Tip of #{branch} at that time: #{head['commitId']} (#{head.dig('committer', 'date')}).",
            "This is a guess from the default branch, not proof it was deployed. Say so when relying on it."
          ]
          lines << if base && base["commitId"] != head["commitId"]
            "What reached #{branch} in the #{NO_DEPLOY_LOOKBACK.inspect} before: compare_commits with base #{base['commitId']} and head #{head['commitId']}."
          else
            "Nothing reached #{branch} in the #{NO_DEPLOY_LOOKBACK.inspect} before."
          end
          lines.join("\n")
        end

        def commit_on_branch_at(azure, repo, branch, at)
          azure.values(azure.get("#{path_of(repo)}/commits", "searchCriteria.itemVersion.version" => branch, "searchCriteria.itemVersion.versionType" => "branch",
                                                             "searchCriteria.toDate" => at.iso8601, "searchCriteria.$top" => 1)).first
        end

        # What each of the project's environments last received, for ci_status.
        def environments_text(azure, project)
          path = AzureDevopsApi.project(project)
          environments = azure.values(azure.get("#{path}/_apis/distributedtask/environments", "$top" => ENVIRONMENTS_READ * 5))
          return nil if environments.empty?

          shown = environments.sort_by { |environment| environment["name"].to_s.match?(CodeHost::PRODUCTION) ? 0 : 1 }.first(ENVIRONMENTS_SHOWN)
          lines = shown.map do |environment|
            record = azure.values(azure.get("#{path}/_apis/distributedtask/environments/#{environment['id']}/environmentdeploymentrecords", "top" => 1)).first
            last = record ? "#{record['result'] || 'running'} run #{record.dig('owner', 'name')} of #{record.dig('definition', 'name')} at #{record['startTime'] || record['queueTime']}" : "nothing deployed yet"
            "  #{environment['name']}: #{last}"
          end
          more = environments.size > ENVIRONMENTS_SHOWN ? "\n  #{environments.size - ENVIRONMENTS_SHOWN} more environments, recent_deployments reads them." : ""
          "Environments, what each last received:\n#{lines.join("\n")}#{more}"
        rescue AzureDevopsApi::Refused
          nil
        end
      end
    end
  end
end
