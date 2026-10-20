module Integrations
  module Packs
    class Circleci
      # What a project deployed, as CircleCI's deploy markers record it (v2 listComponents, listComponentVersions and
      # listEnvironments, guides/deploy/configure-deploy-markers): each component a project deploys, each version it
      # deployed to each environment, which one is live there, when it was last deployed and the workflow that did it.
      # A rollback runs the project's rollback pipeline for one component in one environment (v2 rollbackProject,
      # guides/deploy/rollback-a-deployment), which needs a rollback pipeline set up, and otherwise is refused with the
      # workflow that deployed the version, which rerunning deploys again.
      module Deploys
        DEPLOY_LIMIT = 20
        MOST_DEPLOYS = 100

        def self.included(pack)
          pack.tool :list_deploys,
                    summary: "Lists what a project's components deployed to each environment and which version is live.",
                    description: "What a project deployed, newest first: each component's versions in each environment, which is live, when " \
                                 "it was last deployed and the workflow that deployed it. Each deploy's id, component/environment/version, " \
                                 "is what rollback_deploy and rollback take. Projects record deploys with CircleCI's deploy markers",
                    params_schema: { "type" => "object", "properties" => {
                      "project" => Circleci::PROJECT_PARAM,
                      "environment" => { "type" => "string", "description" => "Only deploys to this environment, by its name (optional)" },
                      "component" => { "type" => "string", "description" => "Only this component, by its name (optional)" },
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{DEPLOY_LIMIT}, at most #{MOST_DEPLOYS})" }
                    }, "required" => %w[project] },
                    read_only: true

          pack.tool :rollback_deploy,
                    summary: "Rolls a component back to an earlier version in one environment.",
                    description: "Roll one component back to an earlier version in one environment, through the project's rollback pipeline, " \
                                 "from the version live there now. list_deploys gives the component, environment and versions",
                    params_schema: { "type" => "object", "properties" => {
                      "project" => Circleci::PROJECT_PARAM,
                      "component" => { "type" => "string", "description" => "The component, by its name" },
                      "environment" => { "type" => "string", "description" => "The environment, by its name" },
                      "version" => { "type" => "string", "description" => "The version to go back to" },
                      "reason" => { "type" => "string", "description" => "Why, which CircleCI keeps with the rollback (optional)" }
                    }, "required" => %w[project component environment version] },
                    read_only: false
        end

        def list_deploys(environment_row:, arguments:)
          project = find_project(environment_row, arguments)
          limit = whole_number_argument(arguments, "limit", DEPLOY_LIMIT, MOST_DEPLOYS)
          deploys = deploys_of(environment_row, project).select do |deploy|
            named?(deploy[:component], arguments["component"]) && named?(deploy[:environment], arguments["environment"])
          end.first(limit)
          link = project_link(environment_row, project)
          if deploys.empty?
            return Capabilities::Deploys.with_deploys(Telemetry.result("#{project.label} has no deploys CircleCI recorded that match. A project records them " \
                                                                       "with deploy markers in its config.", link: link), [])
          end

          lines = deploys.map { |deploy| deploy_line(deploy) }
          result = Telemetry.result("Latest #{lines.size} deploys of #{project.label}, newest first. rollback_deploy takes a component, an environment " \
                                    "and a version.\n#{lines.join("\n")}", link: link)
          Capabilities::Deploys.with_deploys(result, deploys.map { |deploy| as_deploy(deploy) })
        end

        def rollback_deploy(environment_row:, arguments:)
          project = find_project(environment_row, arguments)
          component, environment, version = %w[component environment version].map { |key| arguments[key].to_s.strip.presence || fail!("Say which #{key}. list_deploys shows them.") }
          deploys = deploys_of(environment_row, project).select { |deploy| deploy[:component].casecmp?(component) && deploy[:environment].casecmp?(environment) }
          fail! "#{project.label} deployed no component #{component} to #{environment}. list_deploys shows what it deployed." if deploys.empty?

          live = deploys.find { |deploy| deploy[:live] } || fail!("#{component} has no version live in #{environment}, so there is nothing to roll back from.")
          target = deploys.find { |deploy| deploy[:version] == version } || fail!("#{component} never deployed #{version} to #{environment}. list_deploys shows its versions.")
          fail! "#{version} is already live in #{environment}." if target[:version] == live[:version]

          body = { "component_name" => live[:component], "environment_name" => live[:environment], "current_version" => live[:version],
                   "target_version" => target[:version], "namespace" => live[:namespace], "reason" => arguments["reason"].to_s.strip.presence }.compact
          rolled = begin
            api(environment_row).rollback(project.id, body)
          rescue CircleciApi::Refused => error
            rerun = target[:workflow_id] ? " Without one, rerunning workflow #{target[:workflow_id]}, which deployed #{version}, deploys it again." : ""
            fail! Sentence.join("CircleCI refused to roll #{component} back in #{environment}", error,
                                after: "A rollback runs the project's rollback pipeline, which has to be set up in CircleCI.#{rerun}")
          end
          undo = live[:workflow_id] ? " To undo it, rerun workflow #{live[:workflow_id]}, which deployed #{live[:version]}." : " #{live[:version]} was live before."
          Telemetry.result("Rolling #{component} back in #{environment} from #{live[:version]} to #{version} (#{rolled['rollback_type'] || 'rollback'} " \
                           "#{rolled['id']}).#{undo}", link: project_link(environment_row, project))
        end

        private

        def named?(value, asked) = asked.to_s.strip.empty? || value.to_s.casecmp?(asked.to_s.strip)

        # Every version each of the project's components deployed, newest first, with its environment's name.
        def deploys_of(environment_row, project)
          environments = api(environment_row).environments(project.org_id).to_h { |environment| [ environment["id"], environment["name"] ] }
          api(environment_row).components(project.org_id, project.id).flat_map do |component|
            api(environment_row).versions(component["id"]).map do |version|
              { component: component["name"].to_s, environment: environments.fetch(version["environment_id"], version["environment_id"]).to_s,
                version: version["name"].to_s, live: version["is_live"] == true, at: version["last_deployed_at"], namespace: version["namespace"].presence,
                workflow_id: version["workflow_id"], job_number: version["job_number"] }
            end
          end.sort_by { |deploy| deploy[:at].to_s }.reverse
        end

        def deploy_line(deploy)
          [ "#{deploy[:component]}/#{deploy[:environment]}/#{deploy[:version]}", ("live" if deploy[:live]), ("last deployed #{deploy[:at]}" if deploy[:at]),
            ("namespace #{deploy[:namespace]}" if deploy[:namespace]), ("by workflow #{deploy[:workflow_id]}" if deploy[:workflow_id]),
            ("job ##{deploy[:job_number]}" if deploy[:job_number]) ].compact.join(", ")
        end

        # A recorded version was deployed, so it rolled out. The one live is the one serving.
        def as_deploy(deploy)
          Capabilities::Deploys::Deploy.new(id: "#{deploy[:component]}/#{deploy[:environment]}/#{deploy[:version]}", version: deploy[:version],
                                            status: Capabilities::History::SUCCEEDED, live: deploy[:live], started_at: deploy[:at], finished_at: deploy[:at],
                                            environment: deploy[:environment])
        end

        # What each component runs in each environment now, for ci_status.
        def deployed_text(environment_row, project)
          live = deploys_of(environment_row, project).select { |deploy| deploy[:live] }
          return if live.empty?

          "Live now:\n#{live.map { |deploy| "  #{deploy[:component]} in #{deploy[:environment]}: #{deploy[:version]}, deployed #{deploy[:at]}" }.join("\n")}"
        rescue CircleciApi::Error
          nil
        end
      end
    end
  end
end
