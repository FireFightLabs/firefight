module Integrations
  module Packs
    class Railway < NativePack
      # The changes Railway makes to one deployment beside a restart and a rollback, each the mutation Railway's API docs
      # give (railwayapp/docs, content/docs/integrations/api/manage-deployments.md) and the schema names
      # (Mutation.deploymentCancel, deploymentStop, deploymentRedeploy, deploymentApprove). Each acts only on a deployment of
      # the service in the environment the call reads, so an id never reaches past what the connection reads.
      module Deployments
        CANCEL_DEPLOYMENT = "cancel_deployment".freeze
        STOP_DEPLOYMENT = "stop_deployment".freeze
        REDEPLOY_DEPLOYMENT = "redeploy_deployment".freeze
        APPROVE_DEPLOYMENT = "approve_deployment".freeze
        # A deployment Railway has not finished building or deploying, which it can cancel (docs, Cancel a deployment that
        # is building or queued, and the dashboard's Abort deployment).
        IN_PROGRESS = %w[INITIALIZING QUEUED WAITING NEEDS_APPROVAL BUILDING DEPLOYING].freeze
        # A deployment whose replicas run or sleep, which Railway can stop.
        RUNNING = %w[SUCCESS SLEEPING CRASHED].freeze
        # A deployment Railway holds for someone to approve, such as a push by a GitHub user with no linked Railway account
        # (docs, content/docs/services.md, Approving a deployment).
        AWAITING_APPROVAL = %w[NEEDS_APPROVAL WAITING].freeze
        STOPPING_TOOLS = [ CANCEL_DEPLOYMENT, STOP_DEPLOYMENT ].freeze
        # A stop with no deployment named takes the one serving, not the newest, which may be queued or failed.
        SERVING = :serving

        def self.included(pack)
          pack.tool CANCEL_DEPLOYMENT,
                    summary: "Cancels a deployment that is still queued, building or deploying.",
                    description: "Cancel a deployment of a service that is still queued, waiting, building or deploying, by the id " \
                                 "list_deployments shows. The deployment serving before it keeps serving",
                    params_schema: deployment_schema("The deployment to cancel, by its id", required: true),
                    read_only: false

          pack.tool STOP_DEPLOYMENT,
                    summary: "Stops a service's running deployment, so it serves nothing.",
                    description: "Stop the replicas of a service's deployment that runs, by its id or the one serving now. The service serves " \
                                 "nothing until restart_deployment starts it again or a new deployment goes live",
                    params_schema: deployment_schema("The deployment to stop, by its id (optional, the one serving now, even when a newer one is queued or failed)"),
                    read_only: false

          pack.tool REDEPLOY_DEPLOYMENT,
                    summary: "Redeploys a deployment with the same code and settings.",
                    description: "Make a new deployment of a service from a deployment that succeeded, failed or crashed, by its id " \
                                 "or the latest, with the same code and build and deploy settings, built again. Follow it with " \
                                 "deploy_history and the new deployment's id as run",
                    params_schema: deployment_schema("The deployment to redeploy, by its id (optional, the latest)"),
                    read_only: false

          pack.tool APPROVE_DEPLOYMENT,
                    summary: "Approves a deployment Railway holds for approval, so it deploys.",
                    description: "Approve a deployment Railway holds until someone approves it, such as a push to a connected branch by " \
                                 "a GitHub user with no linked Railway account. Railway then builds and deploys it",
                    params_schema: deployment_schema("The deployment to approve, by its id", required: true),
                    read_only: false
        end

        def self.deployment_schema(words, required: false)
          {
            "type" => "object",
            "properties" => { "resource" => RESOURCE, "deployment" => { "type" => "string", "description" => words } },
            "required" => required ? %w[resource deployment] : %w[resource]
          }
        end

        def cancel_deployment(environment_row:, arguments:)
          resource, deployment = named_deployment(environment_row, arguments, latest: false)
          unless IN_PROGRESS.include?(deployment["status"])
            fail! "Deployment #{deployment['id']} of #{resource[:name]} is #{deployment['status'].to_s.downcase}, so there is nothing to cancel."
          end

          api(environment_row).cancel(deployment["id"])
          Telemetry.result("Railway is cancelling deployment #{deployment['id']} of #{resource[:name]}, which was #{deployment['status'].to_s.downcase}. " \
                           "The deployment serving before it keeps serving.", link: link(environment_row, resource))
        end

        def stop_deployment(environment_row:, arguments:)
          resource, deployment = named_deployment(environment_row, arguments, latest: SERVING)
          unless RUNNING.include?(deployment["status"])
            fail! "Deployment #{deployment['id']} of #{resource[:name]} is #{deployment['status'].to_s.downcase}, so it runs nothing to stop."
          end

          api(environment_row).stop(deployment["id"])
          Telemetry.result("Railway is stopping deployment #{deployment['id']} of #{resource[:name]}. It serves nothing until restart_deployment starts " \
                           "it again or a new deployment goes live.", link: link(environment_row, resource))
        end

        def redeploy_deployment(environment_row:, arguments:)
          resource, deployment = named_deployment(environment_row, arguments, latest: true)
          fail! "Railway cannot redeploy deployment #{deployment['id']} of #{resource[:name]}, which is #{deployment['status'].to_s.downcase}." unless deployment["canRedeploy"]

          made = api(environment_row).redeploy(deployment["id"])
          Telemetry.result("Railway is redeploying #{resource[:name]} from deployment #{deployment['id']}#{", as deployment #{made['id']}" if made['id']}, " \
                           "building the same code with the same settings. Follow it with deploy_history#{" and run #{made['id']}" if made['id']}.",
                           link: link(environment_row, resource))
        end

        def approve_deployment(environment_row:, arguments:)
          resource, deployment = named_deployment(environment_row, arguments, latest: false)
          unless AWAITING_APPROVAL.include?(deployment["status"])
            fail! "Deployment #{deployment['id']} of #{resource[:name]} is #{deployment['status'].to_s.downcase}, not waiting for approval."
          end

          api(environment_row).approve(deployment["id"])
          Telemetry.result("Approved deployment #{deployment['id']} of #{resource[:name]}, so Railway builds and deploys it. Follow it with deploy_history " \
                           "and run #{deployment['id']}.", link: link(environment_row, resource))
        end

        # Whoever started the deployment a cancel or a stop would end, as Railway names its creator. A deployment Railway
        # started on its own, such as one from a push, names nobody.
        def owner_of(tool_name, environment_row:, arguments:)
          return super unless STOPPING_TOOLS.include?(tool_name)

          resource, deployment = named_deployment(environment_row, arguments, latest: (SERVING if tool_name == STOP_DEPLOYMENT))
          creator = deployment["creator"].to_h
          return if creator["name"].blank? && creator["email"].blank?

          Owner.new(name: creator["name"].presence || creator["email"], email: creator["email"].presence,
                    role: tool_name == STOP_DEPLOYMENT ? Owner::ROLE_DEPLOYED : Owner::ROLE_STARTED,
                    what: "deployment #{deployment['id']} of #{resource[:name]}")
        end

        private

        # The service and the deployment a call names, read whole, or its latest when latest is allowed and none was named.
        def named_deployment(environment_row, arguments, latest:)
          resource = find_resource(environment_row, arguments["resource"])
          id = arguments["deployment"].to_s.strip.presence
          id ||= (latest == SERVING ? serving_id(environment_row, resource) : resource[:instance].dig("latestDeployment", "id")) if latest
          fail!(latest ? "#{resource[:name]} has no #{latest == SERVING ? 'running deployment' : 'deployment yet'}." : "Say which deployment, by the id list_deployments shows.") unless id

          [ resource, own_deployment!(environment_row, resource, id) ]
        end

        # The newest deployment whose replicas run or sleep, which is what serves even while a newer one is queued or failed.
        def serving_id(environment_row, resource)
          api(environment_row).deployments(project_of(environment_row), environment(environment_row)["id"], resource[:id], limit: ROLLBACK_LOOKUP)
                              .find { |deployment| RUNNING.include?(deployment["status"]) }&.dig("id")
        end
      end
    end
  end
end
