module Integrations
  module Packs
    class Aws < NativePack
      # What releases code on AWS rather than running it: CodePipeline pipelines, CodeDeploy deployment groups and
      # CloudFormation stacks, on the map and as run history, and the changes that stop or roll one back. Each read and
      # change uses the operations, fields and states the API references of CodePipeline, CodeDeploy, CloudFormation and
      # ECS give. A pipeline links what its deploy actions name (CodePipeline user guide, Action structure reference: ECS
      # ClusterName and ServiceName, CodeDeploy ApplicationName and DeploymentGroupName, CloudFormation StackName, Elastic
      # Beanstalk ApplicationName and EnvironmentName), a deployment group the ECS services it lists (ecsServices), and a
      # stack the resources CloudFormation tagged with its id (aws:cloudformation:stack-id, CloudFormation user guide,
      # Resource tag), each as released_by.
      module Releases
        History = Capabilities::History

        PIPELINE = ResourceMap::KIND_PIPELINE
        DEPLOYMENT_GROUP = ResourceMap::KIND_RELEASE_FLOW
        STACK = ResourceMap::KIND_STACK
        RELEASE_KINDS = { PIPELINE => "CodePipeline pipeline", DEPLOYMENT_GROUP => "CodeDeploy deployment group", STACK => "CloudFormation stack" }.freeze
        # Stacks and deployment groups are read before pipelines, so a pipeline links to the ones its actions name.
        READ_ORDER = [ STACK, DEPLOYMENT_GROUP, PIPELINE ].freeze
        RELEASE_SERVICES = { PIPELINE => "codepipeline", DEPLOYMENT_GROUP => "codedeploy", STACK => "cloudformation" }.freeze
        RELEASE_PLURALS = { PIPELINE => "CodePipeline pipelines", DEPLOYMENT_GROUP => "CodeDeploy deployment groups", STACK => "CloudFormation stacks" }.freeze

        PIPELINE_EXECUTIONS = "pipeline_executions".freeze
        CODEDEPLOY_DEPLOYMENTS = "codedeploy_deployments".freeze
        STACK_EVENTS = "stack_events".freeze
        STOP_SERVICE_DEPLOYMENT = "stop_service_deployment".freeze
        STOP_PIPELINE_EXECUTION = "stop_pipeline_execution".freeze
        ROLLBACK_PIPELINE_STAGE = "rollback_pipeline_stage".freeze
        STOP_CODEDEPLOY_DEPLOYMENT = "stop_codedeploy_deployment".freeze
        CANCEL_STACK_UPDATE = "cancel_stack_update".freeze
        # The pack's own reads a part's log is read with. build_log reads a CodeBuild build's log where the pack has it.
        SEARCH_LOGS = "search_logs".freeze
        BUILD_LOG = "build_log".freeze

        RUN_LIMIT = 20
        # ListActionExecutions answers at most 100 a page, BatchGetDeployments and BatchGetDeploymentTargets 25 a call.
        ACTIONS_PER_PAGE = 100
        DEPLOYMENTS_PER_CALL = 25
        TARGETS_SHOWN = 25
        # DescribeStackEvents answers 100 a page, newest first. A stack's operations are read from this many pages.
        STACK_EVENT_PAGES = 10
        PARTS_SHOWN = 50

        # A pipeline execution's status (PipelineExecutionStatus). Superseded means a newer execution went on in its place.
        EXECUTION_STATUSES = {
          "inprogress" => History::RUNNING, "stopping" => History::RUNNING, "succeeded" => History::SUCCEEDED,
          "superseded" => History::CANCELLED, "stopped" => History::CANCELLED, "cancelled" => History::CANCELLED, "failed" => History::FAILED
        }.freeze
        # An action execution's status (ActionExecutionStatus).
        ACTION_STATUSES = {
          "inprogress" => History::RUNNING, "succeeded" => History::SUCCEEDED, "failed" => History::FAILED, "abandoned" => History::CANCELLED
        }.freeze
        # A CodeDeploy deployment's status (DeploymentStatus). Baking waits out the time set before the old fleet goes, and
        # Ready waits to reroute traffic, both still going.
        DEPLOYMENT_STATUSES = {
          "created" => History::QUEUED, "queued" => History::QUEUED, "inprogress" => History::RUNNING, "baking" => History::RUNNING,
          "ready" => History::RUNNING, "succeeded" => History::SUCCEEDED, "failed" => History::FAILED, "stopped" => History::CANCELLED
        }.freeze
        # A deployment target's and a lifecycle event's status (TargetStatus, LifecycleEventStatus).
        TARGET_STATUSES = {
          "pending" => History::QUEUED, "inprogress" => History::RUNNING, "ready" => History::RUNNING, "succeeded" => History::SUCCEEDED,
          "skipped" => History::SUCCEEDED, "failed" => History::FAILED
        }.freeze
        STACK_TYPE = "AWS::CloudFormation::Stack".freeze
        # A stack status that starts an operation (StackStatus). A rollback goes on as the same operation.
        STACK_BEGINS = %w[CREATE_IN_PROGRESS UPDATE_IN_PROGRESS DELETE_IN_PROGRESS IMPORT_IN_PROGRESS REVIEW_IN_PROGRESS].freeze
        # What CloudFormation tags each resource it makes with (CloudFormation user guide, Resource tag).
        STACK_TAG = "aws:cloudformation:stack-id".freeze
        STACK_UPDATING = %w[UPDATE_IN_PROGRESS].freeze
        # The deploy action providers whose configuration names what they release.
        ECS_PROVIDER = "ECS".freeze
        CODEDEPLOY_PROVIDERS = %w[CodeDeploy CodeDeployToECS].freeze
        CLOUDFORMATION_PROVIDER = "CloudFormation".freeze
        BEANSTALK_PROVIDER = "ElasticBeanstalk".freeze
        CODEBUILD_PROVIDER = "CodeBuild".freeze
        # A pipeline execution's id and an ECS service deployment's id (PipelineExecution.pipelineExecutionId is a UUID, a
        # service deployment's id is the last part of its ARN).
        EXECUTION_ID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
        SERVICE_DEPLOYMENT_ARN = %r{\Aarn:[a-z-]+:ecs:[a-z0-9-]+:\d{12}:service-deployment/[^/]+/[^/]+/(?<id>[A-Za-z0-9_-]+)\z}
        SERVICE_DEPLOYMENT_ID = /\A[A-Za-z0-9_-]*[A-Za-z_-][A-Za-z0-9_-]*\z/
        CODEDEPLOY_ID = /\Ad-[A-Z0-9]{9}\z/
        # StopServiceDeployment's stopType.
        ROLLBACK_MODE = "rollback".freeze
        STOP_TYPES = { ROLLBACK_MODE => "ROLLBACK", "abort" => "ABORT" }.freeze

        RELEASE_RESOURCE = { "type" => "string", "description" => "A CodePipeline pipeline, CodeDeploy deployment group (application/group) or " \
                                                                   "CloudFormation stack, by its name or ARN" }.freeze

        def self.included(pack)
          pack.tool PIPELINE_EXECUTIONS,
                    summary: "Lists a CodePipeline pipeline's recent runs and how each stage went.",
                    description: "A CodePipeline pipeline's recent executions, newest first, each with its status, when it started and " \
                                 "finished, the source revision and what started it, and how long finished ones usually take. Name an " \
                                 "execution to read it with each stage's actions, how each went, the error a failed one gave and where its log is",
                    params_schema: history_schema("The pipeline, by its name or ARN"),
                    read_only: true

          pack.tool CODEDEPLOY_DEPLOYMENTS,
                    summary: "Lists a CodeDeploy deployment group's recent deployments and any rollbacks.",
                    description: "A CodeDeploy deployment group's recent deployments, newest first, each with its status, when it started " \
                                 "and finished, the revision and any rollback, and how long finished ones usually take. Name a deployment " \
                                 "to read it with each target's lifecycle events and the error a failed one gave",
                    params_schema: history_schema("The deployment group, as application/group or its ARN"),
                    read_only: true

          pack.tool STACK_EVENTS,
                    summary: "Lists a CloudFormation stack's recent changes and the first resource that failed.",
                    description: "A CloudFormation stack's recent operations (create, update, delete), newest first, read from its events, " \
                                 "each with how it ended and the first resource that failed. Name an operation to read it with each " \
                                 "resource it changed and why one failed",
                    params_schema: history_schema("The stack, by its name or stack id"),
                    read_only: true

          pack.tool STOP_SERVICE_DEPLOYMENT,
                    summary: "Stops an ECS deployment in progress, rolling it back or leaving it where it is.",
                    description: "Stop an ECS service deployment that is still going, rolling the service back to the revision it ran before " \
                                 "(rollback) or leaving it where it is (abort). list_deployments shows the deployments",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "resource" => { "type" => "string", "description" => "The ECS service, by its name or ARN" },
                        "deployment" => { "type" => "string", "description" => "The deployment to stop, by its id or ARN as list_deployments shows it" },
                        "mode" => { "type" => "string", "enum" => STOP_TYPES.keys, "description" => "rollback or abort (optional, rollback)" }
                      },
                      "required" => %w[resource deployment]
                    },
                    read_only: false

          pack.tool STOP_PIPELINE_EXECUTION,
                    summary: "Stops a CodePipeline run that is still going.",
                    description: "Stop a CodePipeline execution that is still going. By default the actions in progress finish first. With " \
                                 "abandon, they are abandoned at once, which can leave a deployment half done",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "resource" => { "type" => "string", "description" => "The pipeline, by its name or ARN" },
                        "execution" => { "type" => "string", "description" => "The execution to stop, by its id as pipeline_executions shows it" },
                        "abandon" => { "type" => "boolean", "description" => "Abandon the actions in progress rather than let them finish (optional, false)" },
                        "reason" => { "type" => "string", "description" => "Why, kept on the execution (optional)" }
                      },
                      "required" => %w[resource execution]
                    },
                    read_only: false

          pack.tool ROLLBACK_PIPELINE_STAGE,
                    summary: "Rolls one CodePipeline stage back to what an earlier successful run deployed.",
                    description: "Roll one stage of a CodePipeline pipeline back to what an earlier successful execution deployed there. " \
                                 "Only a V2 pipeline can, and the stage must not be the source stage",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "resource" => { "type" => "string", "description" => "The pipeline, by its name or ARN" },
                        "stage" => { "type" => "string", "description" => "The stage to roll back, by its name (optional when one stage deploys)" },
                        "to" => { "type" => "string", "description" => "The earlier execution whose deployment to go back to, by its id" }
                      },
                      "required" => %w[resource to]
                    },
                    read_only: false

          pack.tool STOP_CODEDEPLOY_DEPLOYMENT,
                    summary: "Stops a CodeDeploy deployment in progress and rolls back what it changed.",
                    description: "Stop a CodeDeploy deployment that is still going, and by default roll back what it already changed to the " \
                                 "revision deployed before",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "resource" => { "type" => "string", "description" => "The deployment group, as application/group or its ARN" },
                        "deployment" => { "type" => "string", "description" => "The deployment, by its id such as d-ABCDEF123" },
                        "roll_back" => { "type" => "boolean", "description" => "Roll back what it changed (optional, true)" }
                      },
                      "required" => %w[resource deployment]
                    },
                    read_only: false

          pack.tool CANCEL_STACK_UPDATE,
                    summary: "Cancels a CloudFormation stack update in progress and rolls the stack back.",
                    description: "Cancel a CloudFormation stack update that is still going, which rolls the stack back to how it was before",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "resource" => { "type" => "string", "description" => "The stack, by its name or stack id" },
                        "operation" => { "type" => "string", "description" => "The update to cancel, by its id as stack_events shows it (optional, the one going)" }
                      },
                      "required" => [ "resource" ]
                    },
                    read_only: false
        end

        def self.history_schema(resource)
          {
            "type" => "object",
            "properties" => {
              "resource" => { "type" => "string", "description" => resource },
              "run" => { "type" => "string", "description" => "Only this one, by its id, with each of its steps (optional)" },
              "name" => { "type" => "string", "description" => "Only runs whose name contains this (optional)" },
              "limit" => { "type" => "integer", "description" => "At most this many (optional, #{RUN_LIMIT})" }
            },
            "required" => [ "resource" ]
          }
        end

        # A pipeline's executions from ListPipelineExecutions, or one by its id from GetPipelineExecution with each action
        # from ListActionExecutions, read however old it is.
        def pipeline_executions(environment_row:, arguments:)
          target = release_target!(environment_row, arguments["resource"], PIPELINE)
          aws = api(environment_row)
          what = "pipeline #{target.name}"
          if arguments["run"].present?
            id = arguments["run"].to_s.strip.delete_prefix("#")
            execution = aws.call(:codepipeline, target.region, :get_pipeline_execution, pipeline_name: target.name, pipeline_execution_id: id)[:pipeline_execution]
            fail!("#{target.name} has no execution #{id}. pipeline_executions shows its executions.") unless execution

            definition = aws.call(:codepipeline, target.region, :get_pipeline, name: target.name)[:pipeline] || {}
            run = execution_run(target, execution).with(parts: action_parts(environment_row, target, id, definition))
            return release_result([ run ], what, release_link(target))
          end

          limit = Capabilities::Answers.limit(arguments, RUN_LIMIT)
          executions = Array(aws.call(:codepipeline, target.region, :list_pipeline_executions, pipeline_name: target.name, max_results: limit)[:pipeline_execution_summaries])
          release_result(executions.map { |execution| execution_run(target, execution) }, what, release_link(target), name: arguments["name"], limit: limit)
        end

        # A deployment group's deployments from ListDeployments and BatchGetDeployments, or one by its id with each target's
        # lifecycle events (ListDeploymentTargets, BatchGetDeploymentTargets).
        def codedeploy_deployments(environment_row:, arguments:)
          target = release_target!(environment_row, arguments["resource"], DEPLOYMENT_GROUP)
          application, group = target.name.split("/", 2)
          aws = api(environment_row)
          what = "deployment group #{target.name}"
          if arguments["run"].present?
            id = arguments["run"].to_s.strip
            deployment = Array(aws.call(:codedeploy, target.region, :batch_get_deployments, deployment_ids: [ id ])[:deployments_info]).first
            unless deployment && deployment[:deployment_group_name] == group && deployment[:application_name] == application
              fail!("#{target.name} has no deployment #{id}. codedeploy_deployments shows its deployments.")
            end

            run = deployment_run(target, deployment).with(parts: target_parts(environment_row, target, deployment))
            return release_result([ run ], what, deployment_link(target, id))
          end

          limit = Capabilities::Answers.limit(arguments, RUN_LIMIT)
          ids = Array(aws.call(:codedeploy, target.region, :list_deployments, application_name: application, deployment_group_name: group)[:deployments])
          deployments = ids.first(limit).each_slice(DEPLOYMENTS_PER_CALL).flat_map do |slice|
            Array(aws.call(:codedeploy, target.region, :batch_get_deployments, deployment_ids: slice)[:deployments_info])
          end
          release_result(deployments.map { |deployment| deployment_run(target, deployment) }, what, release_link(target), name: arguments["name"], limit: limit)
        end

        # A stack's operations, read from its events (DescribeStackEvents, newest first). Events of one operation share its
        # OperationId. An event from before CloudFormation kept one joins the operation its stack's own status began.
        def stack_events(environment_row:, arguments:)
          target = release_target!(environment_row, arguments["resource"], STACK)
          wanted = arguments["run"].to_s.strip.presence
          operations, cut = stack_operations(environment_row, target, wanted)
          what = "stack #{target.name}"
          if wanted
            operation = operations.find { |each| each.first == wanted }
            fail!("#{target.name} has no operation #{wanted} in its recent events. stack_events shows its operations.") unless operation

            run = stack_run(target, *operation).then { |found| found.with(parts: stack_parts(target, operation.last)) }
            return release_result([ run ], what, release_link(target))
          end

          limit = Capabilities::Answers.limit(arguments, RUN_LIMIT)
          runs = operations.map { |id, events| stack_run(target, id, events) }
          result = release_result(runs, what, release_link(target), name: arguments["name"], limit: limit)
          return result unless cut

          note = "CloudFormation keeps more events than Firefight read, so older operations are not shown."
          result.merge("content" => [ { "type" => "text", "text" => "#{result.dig('content', 0, 'text')}\n#{note}" } ])
        end

        def stop_service_deployment(environment_row:, arguments:)
          entry = ecs_service!(environment_row, arguments["resource"], "have deployments to stop")
          id = service_deployment_id(arguments["deployment"])
          mode = arguments["mode"].to_s.strip.downcase.presence || ROLLBACK_MODE
          stop_type = STOP_TYPES[mode] || fail!("mode must be rollback or abort.")
          prefix = entry.arn.match(ARN)
          arn = "arn:#{prefix[:partition]}:ecs:#{entry.region}:#{prefix[:account]}:service-deployment/#{entry.cluster}/#{entry.name}/#{id}"
          deployment = Array(api(environment_row).call(:ecs, entry.region, :describe_service_deployments, service_deployment_arns: [ arn ])[:service_deployments]).first
          fail!("ECS has no deployment #{id} of #{entry.name}. list_deployments shows its deployments.") unless deployment
          unless %w[PENDING IN_PROGRESS].include?(deployment[:status])
            fail!("Deployment #{id} of #{entry.name} is #{deployment[:status].to_s.downcase.tr('_', ' ')}, so there is nothing to stop.")
          end

          changing(entry) do
            api(environment_row).call(:ecs, entry.region, :stop_service_deployment, service_deployment_arn: arn, stop_type: stop_type)
          end
          words = stop_type == "ROLLBACK" ? "is stopping and rolling #{entry.name} back to the revision it ran before" : "is stopping, leaving #{entry.name} where it is"
          Telemetry.result("Deployment #{id} #{words}. Follow it with list_deployments.", link: resource_link(entry))
        end

        def stop_pipeline_execution(environment_row:, arguments:)
          target = release_target!(environment_row, arguments["resource"], PIPELINE)
          id = execution_id(arguments["execution"])
          execution = execution_now(environment_row, target, id)
          fail!("Execution #{id} of #{target.name} is #{execution[:status].to_s.downcase}, so there is nothing to stop.") unless execution[:status] == "InProgress"

          abandon = ActiveModel::Type::Boolean.new.cast(arguments["abandon"]) == true
          changing(target) do
            api(environment_row).call(:codepipeline, target.region, :stop_pipeline_execution,
                                      { pipeline_name: target.name, pipeline_execution_id: id, abandon: abandon, reason: arguments["reason"].to_s.strip.presence }.compact)
          end
          how = abandon ? "Its actions in progress were abandoned, so a deployment may be half done." : "Its actions in progress finish first."
          Telemetry.result("Execution #{id} of #{target.name} is stopping. #{how} Follow it with pipeline_executions.", link: release_link(target))
        end

        # RollbackStage takes a stage and an earlier execution that succeeded in it. With no stage named, the one stage
        # whose actions deploy is meant, and with several the refusal names them.
        def rollback_pipeline_stage(environment_row:, arguments:)
          target = release_target!(environment_row, arguments["resource"], PIPELINE)
          to = execution_id(arguments["to"])
          definition = api(environment_row).call(:codepipeline, target.region, :get_pipeline, name: target.name)[:pipeline] || {}
          stages = Array(definition[:stages])
          stage = stage_of(stages, arguments["stage"], target)
          execution = execution_now(environment_row, target, to)
          fail!("Execution #{to} of #{target.name} #{execution[:status].to_s.downcase}, and only one that succeeded can be gone back to.") unless execution[:status] == "Succeeded"

          changing(target) do
            api(environment_row).call(:codepipeline, target.region, :rollback_stage, pipeline_name: target.name, stage_name: stage, target_pipeline_execution_id: to)
          end
          Telemetry.result("Stage #{stage} of #{target.name} is rolling back to what execution #{to} deployed. Follow it with pipeline_executions.",
                           link: release_link(target))
        end

        def stop_codedeploy_deployment(environment_row:, arguments:)
          target = release_target!(environment_row, arguments["resource"], DEPLOYMENT_GROUP)
          id = arguments["deployment"].to_s.strip
          fail!("deployment must be the deployment's id, such as d-ABCDEF123, as codedeploy_deployments shows it.") unless id.match?(CODEDEPLOY_ID)

          application, group = target.name.split("/", 2)
          deployment = Array(api(environment_row).call(:codedeploy, target.region, :batch_get_deployments, deployment_ids: [ id ])[:deployments_info]).first
          fail!("#{target.name} has no deployment #{id}.") unless deployment && deployment[:application_name] == application && deployment[:deployment_group_name] == group
          status = History.status(deployment[:status], DEPLOYMENT_STATUSES)
          fail!("Deployment #{id} is #{deployment[:status].to_s.downcase}, so there is nothing to stop.") if History::FINISHED.include?(status)

          roll_back = arguments.key?("roll_back") ? ActiveModel::Type::Boolean.new.cast(arguments["roll_back"]) != false : true
          changing(target) do
            api(environment_row).call(:codedeploy, target.region, :stop_deployment, deployment_id: id, auto_rollback_enabled: roll_back)
          end
          how = roll_back ? "and rolling back what it changed to the revision deployed before" : "leaving what it changed in place"
          Telemetry.result("Deployment #{id} of #{target.name} is stopping, #{how}. Follow it with codedeploy_deployments.", link: deployment_link(target, id))
        end

        # Only an update still going can be cancelled, and when an operation is named it must be the one going, so a
        # cancel meant for one update never lands on the next.
        def cancel_stack_update(environment_row:, arguments:)
          target = release_target!(environment_row, arguments["resource"], STACK)
          stack = Array(api(environment_row).call(:cloudformation, target.region, :describe_stacks, stack_name: target.arn)[:stacks]).first
          fail!("CloudFormation has no stack #{target.name}.") unless stack
          unless STACK_UPDATING.include?(stack[:stack_status])
            fail!("#{target.name} is #{stack[:stack_status].to_s.downcase.tr('_', ' ')}. Only an update still going can be cancelled.")
          end

          wanted = arguments["operation"].to_s.strip.presence
          if wanted
            going = stack_operations(environment_row, target, nil).first.first&.first
            fail!("Operation #{wanted} of #{target.name} is not the update going now (#{going || 'unknown'}), so nothing was cancelled.") if going != wanted
          end
          changing(target) { api(environment_row).call(:cloudformation, target.region, :cancel_update_stack, stack_name: target.arn) }
          Telemetry.result("The update of #{target.name} is being cancelled, and CloudFormation rolls the stack back to how it was before. " \
                           "Follow it with stack_events.", link: release_link(target))
        end

        # The pipelines, deployment groups and stacks of every region the connection reads, with what each releases, as
        # one snapshot beside the rest of the account. entries are the resources already read, which links resolve
        # against so a link is never to a guessed ARN. A list AWS refuses is a gap naming its kind.
        def release_snapshot(environment_row, account, regions, entries)
          found = []
          links = []
          gaps = []
          regions.each do |region|
            READ_ORDER.each do |kind|
              resources, kind_links, more = read_releases(environment_row, account, region, kind, entries + found)
              found.concat(resources)
              links.concat(kind_links)
              gaps << ResourceMap::Gap.new(text: "Only the first #{AwsApi::MAX_PAGES} pages of #{RELEASE_PLURALS.fetch(kind)} in #{region} were read.", kinds: [ kind ]) if more
            rescue Integrations::RateLimited => error
              text = Sentence.join("AWS asked to slow down while listing #{RELEASE_PLURALS.fetch(kind)} in #{region}, so the rest was not read", error)
              return ResourceMap::Snapshot.new(resources: found.map(&:last), links: links, gaps: gaps + [ ResourceMap::Gap.new(text: text, kinds: RELEASE_KINDS.keys) ])
            rescue AwsApi::Error => error
              gaps << ResourceMap::Gap.new(text: Sentence.join("#{RELEASE_PLURALS.fetch(kind)} in #{region} could not be read", error), kinds: [ kind ])
            end
          end
          links.concat(stack_links(account, entries, found))
          ResourceMap::Snapshot.new(resources: found.map(&:last), links: links.uniq, gaps: gaps)
        end

        # One pipeline, deployment group or stack by its ARN, read again with what it releases, for a change an event
        # named. The resources it links to are read from the map, since a re-read only reads the one.
        def release_refresh(environment_row, scope, account, region)
          entries = mapped_entries(environment_row, account)
          resources, links, = read_releases(environment_row, account, region, scope.kind, entries, only: scope.external_id)
          return ResourceMap::Snapshot.new(resources: [], gone: [ [ PROVIDER_KEY, account, scope.kind, scope.external_id ] ]) if resources.empty?

          links += stack_links(account, entries, resources) if scope.kind == STACK
          ResourceMap::Snapshot.new(resources: resources.map(&:last), links: links)
        end

        # The ARN of a pipeline, a deployment group or a stack, in the forms AWS's service authorization reference gives.
        def self.release_arn?(arn) = arn.to_s.match?(/\Aarn:[a-z-]+:(codepipeline|codedeploy|cloudformation):/)

        private

        # A release resource as the tools address it.
        ReleaseTarget = Data.define(:kind, :arn, :name, :region)

        def release_result(runs, what, link, name: nil, limit: RUN_LIMIT)
          History.result(runs, what: what, link: link, name: name, limit: limit)
        end

        def read_releases(environment_row, account, region, kind, known, only: nil)
          case kind
          when PIPELINE then read_pipelines(environment_row, account, region, known, only)
          when DEPLOYMENT_GROUP then read_deployment_groups(environment_row, account, region, known, only)
          else read_stacks(environment_row, account, region, only)
          end
        end

        # Each pipeline with its newest execution's status, and a released_by link from what its deploy actions name.
        def read_pipelines(environment_row, account, region, known, only)
          aws = api(environment_row)
          names, more = only ? [ [ { name: only.split(":", 6).last } ], false ] : aws.all(:codepipeline, region, :list_pipelines, {}, :pipelines)
          found = []
          links = []
          names.each do |listed|
            definition = aws.call(:codepipeline, region, :get_pipeline, name: listed[:name])[:pipeline] || {}
            latest = Array(aws.call(:codepipeline, region, :list_pipeline_executions, pipeline_name: listed[:name], max_results: 1)[:pipeline_execution_summaries]).first
            arn = "arn:#{Aws.partition(region)}:codepipeline:#{region}:#{account}:#{listed[:name]}"
            resource = release_found(account, PIPELINE, arn, listed[:name], region, latest && status_word(latest[:status]),
                                     { "type" => definition[:pipeline_type], "stages" => Array(definition[:stages]).map { |stage| stage[:name] }.join(", ").presence })
            found << [ arn, resource ]
            released_by_pipeline(definition, region, account, known).each { |key| links << ResourceMap::FoundLink.new(from: key, to: resource.key, relation: ResourceMap::RELATION_RELEASED_BY) }
          rescue AwsApi::NotFound
            next
          end
          [ found, links, more ]
        end

        # The keys of what a pipeline's deploy actions name, among what the connection read.
        def released_by_pipeline(definition, region, account, known)
          Array(definition[:stages]).flat_map { |stage| Array(stage[:actions]) }.filter_map do |action|
            type = action[:action_type_id] || {}
            next unless type[:category] == "Deploy"

            config = action[:configuration].to_h.transform_keys(&:to_s)
            where = action[:region].presence || region
            case type[:provider]
            when ECS_PROVIDER
              known_key(known, account) { |entry| entry.kind == SERVICE && entry.region == where && entry.cluster == config["ClusterName"] && entry.name == config["ServiceName"] }
            when *CODEDEPLOY_PROVIDERS
              group_arn = "arn:#{Aws.partition(where)}:codedeploy:#{where}:#{account}:deploymentgroup:#{config['ApplicationName']}/#{config['DeploymentGroupName']}"
              known_key(known, account) { |entry| entry.kind == DEPLOYMENT_GROUP && entry.arn == group_arn }
            when CLOUDFORMATION_PROVIDER
              known_key(known, account) { |entry| entry.kind == STACK && entry.region == where && entry.name == config["StackName"] }
            when BEANSTALK_PROVIDER
              known_key(known, account) { |entry| entry.region == where && entry.details.to_h["application"] == config["ApplicationName"] && entry.name == config["EnvironmentName"] }
            end
          end.uniq
        end

        # known holds entries (Entry) and pairs of an ARN and what was found (ResourceMap::Found), so both are matched alike.
        def known_key(known, account)
          match = known.map { |each| each.is_a?(Array) ? found_entry(each.last) : each }.find { |entry| yield(entry) }
          match && [ PROVIDER_KEY, account, match.kind, match.arn ]
        end

        def found_entry(found)
          details = found.details.to_h
          Entry.new(kind: found.kind, arn: found.external_id, name: found.name, region: details["region"], cluster: details["cluster"], details: details)
        end

        # Each deployment group with its last deployment's status, and a released_by link from each ECS service it lists.
        def read_deployment_groups(environment_row, account, region, known, only)
          aws = api(environment_row)
          pairs, more = if only
            application, group = only.split(":deploymentgroup:", 2).last.to_s.split("/", 2)
            [ [ [ application, group ] ], false ]
          else
            applications, cut = aws.all(:codedeploy, region, :list_applications, {}, :applications)
            listed = applications.flat_map do |application|
              groups, = aws.all(:codedeploy, region, :list_deployment_groups, { application_name: application }, :deployment_groups)
              groups.map { |group| [ application, group ] }
            end
            [ listed, cut ]
          end
          found = []
          links = []
          pairs.group_by(&:first).each do |application, of_application|
            of_application.map(&:last).each_slice(DEPLOYMENTS_PER_CALL * 4) do |names|
              groups = Array(aws.call(:codedeploy, region, :batch_get_deployment_groups, application_name: application, deployment_group_names: names)[:deployment_groups_info])
              groups.each do |group|
                name = "#{application}/#{group[:deployment_group_name]}"
                arn = "arn:#{Aws.partition(region)}:codedeploy:#{region}:#{account}:deploymentgroup:#{name}"
                last = group[:last_attempted_deployment]
                resource = release_found(account, DEPLOYMENT_GROUP, arn, name, region, last && status_word(last[:status]),
                                         { "type" => group[:compute_platform], "application" => application })
                found << [ arn, resource ]
                Array(group[:ecs_services]).each do |service|
                  key = known_key(known, account) { |entry| entry.kind == SERVICE && entry.region == region && entry.cluster == service[:cluster_name] && entry.name == service[:service_name] }
                  links << ResourceMap::FoundLink.new(from: key, to: resource.key, relation: ResourceMap::RELATION_RELEASED_BY) if key
                end
              end
            end
          end
          [ found, links, more ]
        end

        def read_stacks(environment_row, account, region, only)
          stacks, more = api(environment_row).all(:cloudformation, region, :describe_stacks, only ? { stack_name: only } : {}, :stacks)
          found = stacks.reject { |stack| stack[:stack_status] == "DELETE_COMPLETE" }.map do |stack|
            [ stack[:stack_id], release_found(account, STACK, stack[:stack_id], stack[:stack_name], region, stack[:stack_status].to_s.downcase,
                                               { "description" => stack[:description].to_s.truncate(200).presence, ResourceMap::TAGS => tags_of(stack[:tags]) }) ]
          end
          [ found, [], more ]
        rescue AwsApi::Error => error
          raise unless only && error.message.include?("does not exist")

          [ [], [], false ]
        end

        # What CloudFormation made, by the stack id it tagged each resource with.
        def stack_links(account, entries, found)
          stacks = found.map(&:last).select { |resource| resource.kind == STACK }.index_by(&:external_id)
          entries.filter_map do |entry|
            stack = stacks[entry.details.to_h.dig(ResourceMap::TAGS, STACK_TAG)]
            stack && ResourceMap::FoundLink.new(from: [ PROVIDER_KEY, account, entry.kind, entry.arn ], to: stack.key, relation: ResourceMap::RELATION_RELEASED_BY)
          end
        end

        def release_found(account, kind, arn, name, region, status, details)
          ResourceMap::Found.new(provider: PROVIDER_KEY, account: account, kind: kind, external_id: arn, name: name, status: status,
                                 url: release_link(ReleaseTarget.new(kind: kind, arn: arn, name: name, region: region))&.url,
                                 details: { "region" => region, **details }.compact_blank)
        end

        # The map's resources of the connection, for a re-read to link against.
        def mapped_entries(environment_row, account)
          ResourceMap::Resource.present.where(integration_environment: environment_row, provider: PROVIDER_KEY, account: account).map do |resource|
            details = resource.details.to_h
            Entry.new(kind: resource.kind, arn: resource.external_id, name: resource.name, region: details["region"], cluster: details["cluster"], details: details)
          end
        end

        # AWS's own status words, lower case with words joined by an underscore, which the provider's status_words maps.
        def status_word(status) = status.to_s.underscore.presence

        # A pipeline, deployment group or stack by its ARN, or by its name in whichever region holds it.
        def release_target!(environment_row, asked, kind)
          wanted = asked.to_s.strip
          fail!("Say which #{RELEASE_KINDS.fetch(kind)}, by its name or ARN.") if wanted.empty?

          parts = wanted.match(ARN)
          if parts
            fail!("#{wanted} is in #{parts[:region]}, which this connection does not read.") if regions(environment_row).exclude?(parts[:region])
            target = target_from_arn(wanted, parts)
            fail!("#{wanted} is not #{RELEASE_KINDS.fetch(kind).then { |word| "a#{'n' if word.match?(/\A[AEIOU]/)} #{word}" }}.") unless target&.kind == kind

            return target
          end

          listed = regions(environment_row).flat_map { |region| release_names(environment_row, region, kind) }
          Named.find(listed, wanted, id: :arn, name: :name, provider: PROVIDER, describe: ->(target) { "#{target.name} in #{target.region}" }, connection: environment_row) ||
            fail!("No #{RELEASE_KINDS.fetch(kind)} called #{wanted} in #{regions(environment_row).join(', ')}.")
        end

        def target_from_arn(arn, parts)
          resource = parts[:resource]
          case parts[:service]
          when "codepipeline" then ReleaseTarget.new(kind: PIPELINE, arn: arn, name: resource, region: parts[:region])
          when "codedeploy"
            ReleaseTarget.new(kind: DEPLOYMENT_GROUP, arn: arn, name: resource.delete_prefix("deploymentgroup:"), region: parts[:region]) if resource.start_with?("deploymentgroup:")
          when "cloudformation"
            ReleaseTarget.new(kind: STACK, arn: arn, name: resource.split("/")[1], region: parts[:region]) if resource.start_with?("stack/")
          end
        end

        def release_names(environment_row, region, kind)
          account = account_of(environment_row)
          found, = read_names(environment_row, region, kind)
          found.map do |name, arn|
            ReleaseTarget.new(kind: kind, arn: arn || release_arn(kind, region, account, name), name: name, region: region)
          end
        end

        def read_names(environment_row, region, kind)
          aws = api(environment_row)
          case kind
          when PIPELINE then [ aws.all(:codepipeline, region, :list_pipelines, {}, :pipelines).first.map { |listed| [ listed[:name], nil ] } ]
          when DEPLOYMENT_GROUP
            applications, = aws.all(:codedeploy, region, :list_applications, {}, :applications)
            [ applications.flat_map { |application| aws.all(:codedeploy, region, :list_deployment_groups, { application_name: application }, :deployment_groups).first.map { |group| [ "#{application}/#{group}", nil ] } } ]
          else [ aws.all(:cloudformation, region, :describe_stacks, {}, :stacks).first.map { |stack| [ stack[:stack_name], stack[:stack_id] ] } ]
          end
        end

        def release_arn(kind, region, account, name)
          kind == PIPELINE ? "arn:#{Aws.partition(region)}:codepipeline:#{region}:#{account}:#{name}" : "arn:#{Aws.partition(region)}:codedeploy:#{region}:#{account}:deploymentgroup:#{name}"
        end

        # An execution as ListPipelineExecutions or GetPipelineExecution gives it, with the source revision and what started it.
        def execution_run(target, execution)
          revision = Array(execution[:source_revisions] || execution[:artifact_revisions]).first || {}
          trigger = execution[:trigger] || {}
          status = History.status(execution[:status], EXECUTION_STATUSES)
          detail = [ ("#{revision[:action_name] || revision[:name]} #{revision[:revision_id].to_s.first(12)}".strip if revision[:revision_id]),
                     revision[:revision_summary].to_s.lines.first&.strip.presence&.truncate(80),
                     ("started by #{trigger[:trigger_type]}" if trigger[:trigger_type].present?),
                     ("a rollback to #{execution.dig(:rollback_metadata, :rollback_target_pipeline_execution_id)}" if execution.dig(:rollback_metadata, :rollback_target_pipeline_execution_id)),
                     execution[:status_summary].presence ].compact.join(", ").presence
          History::Run.new(id: execution[:pipeline_execution_id], name: target.name, status: status,
                           started_at: Capabilities::RunHistory.time(execution[:start_time]),
                           finished_at: (Capabilities::RunHistory.time(execution[:last_update_time]) if History::FINISHED.include?(status)),
                           detail: detail)
        end

        # Each action of one execution as a part, in the order the pipeline's stages hold them, with how it went, its error,
        # its own page and how to read its log.
        def action_parts(environment_row, target, id, definition)
          details, = api(environment_row).all(:codepipeline, target.region, :list_action_executions,
                                               { pipeline_name: target.name, filter: { pipeline_execution_id: id }, max_results: ACTIONS_PER_PAGE }, :action_execution_details)
          order = Array(definition[:stages]).flat_map { |stage| Array(stage[:actions]).map { |action| [ stage[:name], action[:name] ] } }
          configured = Array(definition[:stages]).flat_map { |stage| Array(stage[:actions]).map { |action| [ [ stage[:name], action[:name] ], action ] } }.to_h
          latest = details.group_by { |each| [ each[:stage_name], each[:action_name] ] }.transform_values { |tries| tries.max_by { |each| each[:start_time] || Time.at(0) } }
          latest.sort_by { |key, _| order.index(key) || order.size }.map do |(stage, action), execution|
            result = execution.dig(:output, :execution_result) || {}
            status = History.status(execution[:status], ACTION_STATUSES)
            started = Capabilities::RunHistory.time(execution[:start_time])
            ended = (Capabilities::RunHistory.time(execution[:last_update_time]) if History::FINISHED.include?(status))
            error = result[:error_details] && [ result.dig(:error_details, :code), result.dig(:error_details, :message) ].compact.join(": ")
            History::Part.new(id: execution[:action_execution_id], name: "#{stage}: #{action}", status: status, started_at: started, finished_at: ended,
                              url: result[:external_execution_url].presence, detail: [ error.presence, result[:external_execution_summary].presence ].compact.join(", ").presence,
                              log: action_log(configured[[ stage, action ]], result, target, started, ended))
          end
        end

        # Where an action's own log is read: a CodeBuild build's log, a CodeDeploy deployment with its lifecycle events, a
        # stack's events, or an ECS service's logs over the time the action ran.
        def action_log(action, result, target, started, ended)
          return unless action

          type = action[:action_type_id] || {}
          config = action[:configuration].to_h.transform_keys(&:to_s)
          region = action[:region].presence || target.region
          external = result[:external_execution_id].presence
          window = { "start" => started&.utc&.iso8601, "end" => (ended || (Time.current if started))&.utc&.iso8601 }.compact
          case type[:provider]
          when CODEBUILD_PROVIDER
            respond_to?(BUILD_LOG) && config["ProjectName"] ? log_handle(BUILD_LOG, { "resource" => config["ProjectName"], "build" => external }.compact) : nil
          when *CODEDEPLOY_PROVIDERS
            group = "#{config['ApplicationName']}/#{config['DeploymentGroupName']}"
            external ? log_handle(CODEDEPLOY_DEPLOYMENTS, { "resource" => group, "run" => external }) : nil
          when CLOUDFORMATION_PROVIDER then config["StackName"] && log_handle(STACK_EVENTS, { "resource" => config["StackName"] })
          when ECS_PROVIDER
            account = target.arn.match(ARN)[:account]
            arn = "arn:#{Aws.partition(region)}:ecs:#{region}:#{account}:service/#{config['ClusterName']}/#{config['ServiceName']}"
            config["ServiceName"] ? log_handle(SEARCH_LOGS, { "resource" => arn }.merge(window)) : nil
          end
        end

        def log_handle(tool, arguments) = { History::LOG_TOOL => tool, History::LOG_ARGUMENTS => arguments }

        # A CodeDeploy deployment, numbered by nothing, named by its group, with its revision and any rollback.
        def deployment_run(target, deployment)
          status = History.status(deployment[:status], DEPLOYMENT_STATUSES)
          revision = deployment[:revision] || {}
          shown = revision.dig(:git_hub_location, :commit_id)&.first(12) || revision.dig(:s3_location, :key) || revision.dig(:app_spec_content, :sha_256)&.first(12)
          detail = [ ("revision #{shown}" if shown), ("rolled back by #{deployment.dig(:rollback_info, :rollback_deployment_id)}" if deployment.dig(:rollback_info, :rollback_deployment_id)),
                     ("a rollback of #{deployment.dig(:rollback_info, :rollback_triggering_deployment_id)}" if deployment.dig(:rollback_info, :rollback_triggering_deployment_id)),
                     deployment.dig(:error_information, :message).presence, ("by #{deployment[:creator]}" if deployment[:creator].present?) ].compact.join(", ").presence
          History::Run.new(id: deployment[:deployment_id], name: target.name, status: status,
                           started_at: Capabilities::RunHistory.time(deployment[:start_time] || deployment[:create_time]),
                           finished_at: (Capabilities::RunHistory.time(deployment[:complete_time]) if History::FINISHED.include?(status)),
                           url: deployment_link(target, deployment[:deployment_id])&.url, detail: detail)
        end

        # An ECS or Lambda deployment has one target, whose lifecycle events are the parts. An EC2 or on-premises one has
        # a target per instance, each a part named by its instance and the lifecycle event it stopped at.
        def target_parts(environment_row, target, deployment)
          aws = api(environment_row)
          ids, = aws.all(:codedeploy, target.region, :list_deployment_targets, { deployment_id: deployment[:deployment_id] }, :target_ids, max_pages: 1)
          return [] if ids.empty?

          found = ids.first(TARGETS_SHOWN).each_slice(DEPLOYMENTS_PER_CALL).flat_map do |slice|
            Array(aws.call(:codedeploy, target.region, :batch_get_deployment_targets, deployment_id: deployment[:deployment_id], target_ids: slice)[:deployment_targets])
          end
          described = found.map { |each| each[:ecs_target] || each[:lambda_target] || each[:instance_target] || each[:cloud_formation_target] || {} }
          if described.one? && (found.first[:ecs_target] || found.first[:lambda_target])
            log = ecs_log(target, deployment, found.first)
            return Array(described.first[:lifecycle_events]).map { |event| lifecycle_part(event, event[:lifecycle_event_name], log) }
          end

          described.map do |each|
            events = Array(each[:lifecycle_events])
            stuck = events.find { |event| event[:status] == "Failed" } || events.reverse.find { |event| event[:status] == "InProgress" }
            name = [ each[:target_id].to_s.split("/").last, stuck && stuck[:lifecycle_event_name] ].compact.join(" at ")
            lifecycle_part(stuck || {}, name, nil).with(id: each[:target_id], status: History.status(each[:status], TARGET_STATUSES))
          end
        end

        def lifecycle_part(event, name, log)
          status = History.status(event[:status], TARGET_STATUSES)
          diagnostics = event[:diagnostics] || {}
          detail = [ diagnostics[:error_code], diagnostics[:message], diagnostics[:script_name] && "script #{diagnostics[:script_name]}" ].compact_blank.join(", ").presence
          started = Capabilities::RunHistory.time(event[:start_time])
          History::Part.new(id: name, name: name, status: status, started_at: started,
                            finished_at: (Capabilities::RunHistory.time(event[:end_time]) if History::FINISHED.include?(status)), detail: detail,
                            log: log && started ? log.merge(History::LOG_ARGUMENTS => log[History::LOG_ARGUMENTS].merge("start" => started.utc.iso8601)) : log)
        end

        # An ECS deployment's target names its cluster and service (ECSTarget.targetId, cluster:service), whose logs are
        # read over the deployment's time.
        def ecs_log(target, deployment, found)
          cluster, service = found.dig(:ecs_target, :target_id).to_s.split(":", 2)
          return unless cluster.present? && service.present?

          account = target.arn.match(ARN)[:account]
          window = { "start" => deployment[:start_time]&.utc&.iso8601, "end" => deployment[:complete_time]&.utc&.iso8601 }.compact
          log_handle(SEARCH_LOGS, { "resource" => "arn:#{Aws.partition(target.region)}:ecs:#{target.region}:#{account}:service/#{cluster}/#{service}" }.merge(window))
        end

        # A stack's operations, newest first, each its id and its events oldest first, and whether events were left unread.
        # With wanted, pages are read until that operation's start is reached.
        def stack_operations(environment_row, target, wanted)
          events = []
          token = nil
          more = false
          STACK_EVENT_PAGES.times do
            page = api(environment_row).call(:cloudformation, target.region, :describe_stack_events, { stack_name: target.arn, next_token: token }.compact)
            events.concat(Array(page[:stack_events]))
            token = page[:next_token]
            more = token.present?
            break unless more
            break if wanted.nil? && grouped(events, target).size > RUN_LIMIT
            break if wanted && begun?(events, target, wanted)
          end
          operations = grouped(events, target)
          # The oldest operation may have begun before the first event read.
          operations = operations[0...-1] if more && operations.size > 1
          [ operations, more ]
        end

        def begun?(events, target, wanted)
          operation = grouped(events, target).find { |id, _| id == wanted }
          operation && stack_level?(operation.last.first, target) && STACK_BEGINS.include?(operation.last.first[:resource_status])
        end

        def grouped(events, target)
          current = nil
          events.sort_by { |event| event[:timestamp] || Time.at(0) }.each_with_object({}) do |event, groups|
            current = event[:event_id] if stack_level?(event, target) && STACK_BEGINS.include?(event[:resource_status])
            key = event[:operation_id].presence || current || event[:event_id]
            (groups[key] ||= []) << event
          end.to_a.reverse
        end

        def stack_level?(event, target) = event[:resource_type] == STACK_TYPE && event[:logical_resource_id] == target.name

        # An operation from its stack's own events: when the first began it, and how the last left the stack.
        def stack_run(target, id, events)
          own = events.select { |event| stack_level?(event, target) }
          first = own.first || events.first
          last = own.last || events.last
          status = stack_status(last[:resource_status], stack: true)
          failed = events.find { |event| !stack_level?(event, target) && event[:resource_status].to_s.end_with?("_FAILED") && event[:resource_status_reason].present? }
          detail = [ last[:resource_status].to_s.downcase.tr("_", " "), failed && "#{failed[:logical_resource_id]}: #{failed[:resource_status_reason]}",
                     (last[:resource_status_reason] if failed.nil? && status == History::FAILED) ].compact_blank.join(", ").presence
          History::Run.new(id: id, name: first[:resource_status].to_s.split("_").first.downcase, status: status,
                           started_at: Capabilities::RunHistory.time(first[:timestamp]),
                           finished_at: (Capabilities::RunHistory.time(last[:timestamp]) if History::FINISHED.include?(status)), detail: detail)
        end

        # Each resource the operation touched, in the order it first moved, with its last status and why it failed.
        def stack_parts(target, events)
          events.reject { |event| stack_level?(event, target) }.group_by { |event| event[:logical_resource_id] }.first(PARTS_SHOWN).map do |logical, own|
            last = own.last
            status = stack_status(last[:resource_status], stack: false)
            reason = own.reverse.find { |event| event[:resource_status].to_s.end_with?("_FAILED") }&.dig(:resource_status_reason)
            History::Part.new(id: logical, name: "#{logical} (#{last[:resource_type]})", status: status, started_at: Capabilities::RunHistory.time(own.first[:timestamp]),
                              finished_at: (Capabilities::RunHistory.time(last[:timestamp]) if History::FINISHED.include?(status)),
                              detail: [ last[:resource_status].to_s.downcase.tr("_", " "), reason ].compact_blank.join(", ").presence)
          end
        end

        # CloudFormation's ResourceStatus in Firefight's words. A stack whose operation ended rolled back failed, and a
        # resource rolled back went back as it should.
        def stack_status(status, stack:)
          word = status.to_s
          return History::RUNNING if word.end_with?("_IN_PROGRESS")
          return History::FAILED if word.end_with?("_FAILED")
          return History::FAILED if stack && word.include?("ROLLBACK")

          History::SUCCEEDED
        end

        def service_deployment_id(given)
          wanted = given.to_s.strip
          return wanted.match(SERVICE_DEPLOYMENT_ARN)[:id] if wanted.match?(SERVICE_DEPLOYMENT_ARN)
          return wanted if wanted.match?(SERVICE_DEPLOYMENT_ID)

          fail!("deployment must be the deployment's id or ARN, as list_deployments shows it.")
        end

        def execution_id(given)
          wanted = given.to_s.strip
          wanted.match?(EXECUTION_ID) ? wanted : fail!("Name the execution by its id, as pipeline_executions shows it.")
        end

        def execution_now(environment_row, target, id)
          api(environment_row).call(:codepipeline, target.region, :get_pipeline_execution, pipeline_name: target.name, pipeline_execution_id: id)[:pipeline_execution] ||
            fail!("#{target.name} has no execution #{id}.")
        rescue AwsApi::NotFound
          fail!("#{target.name} has no execution #{id}. pipeline_executions shows its executions.")
        end

        # The stage named, or the one stage whose actions deploy.
        def stage_of(stages, asked, target)
          names = stages.map { |stage| stage[:name] }
          if asked.present?
            return asked.to_s.strip if names.include?(asked.to_s.strip)

            fail!("#{target.name} has no stage #{asked}. It has #{names.join(', ')}.")
          end
          deploying = stages.select { |stage| Array(stage[:actions]).any? { |action| action.dig(:action_type_id, :category) == "Deploy" } }.map { |stage| stage[:name] }
          return deploying.first if deploying.one?

          fail!("Say which stage of #{target.name} to roll back. #{deploying.any? ? "#{deploying.join(' and ')} deploy" : "It has #{names.join(', ')}"}.")
        end

        # AWS documents no address for one pipeline, deployment group, stack or execution, so each links to its service's
        # list in the console. A CodeDeploy deployment's own page is at the address CodePipeline's events give for a
        # CodeDeploy action (CodePipeline user guide, Monitoring CodePipeline events, Action FAILED event).
        def release_link(target) = console_link(target.region, CONSOLE_PATHS.fetch(RELEASE_SERVICES.fetch(target.kind)))

        def deployment_link(target, id) = console_link(target.region, "codedeploy/home", "/deployments/#{Http.segment(id)}")
      end
    end
  end
end
