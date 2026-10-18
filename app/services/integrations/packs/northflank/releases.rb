module Integrations
  module Packs
    class Northflank < NativePack
      # A project's workflows and its pipelines' release flows, as runs Firefight follows and as resources on the map. A run
      # is a tree of nodes (GetWorkflowrunResult and GetReleaseflowrunResult spec): a Workflow node holds its steps in
      # spec.steps, and every other node has a kind and a response with its status, error, retries and start and end
      # times. What a node made is in its response's data, read as ${refs.<ref>.<field>} in the template, so a Build node's
      # data.id is the build and data.nfObjectId what it built (Make a template dynamic, and Run and manage workflows).
      # The reference documents a node's data only for some kinds, so where the id is not there, a node's log is read
      # over the time it ran.
      module Releases
        WORKFLOW_RUNS = "workflow_runs".freeze
        RELEASE_FLOW_RUNS = "release_flow_runs".freeze
        # The pack's own reads a node's log is read with.
        BUILD_LOGS = "build_logs".freeze
        SEARCH_LOGS = "search_logs".freeze
        KIND_WORKFLOWS = "workflows".freeze
        KIND_PIPELINES = "pipelines".freeze
        # A pipeline's stages (GetPipelineResult nfObjects stage), each with at most one release flow, written in its path
        # in lower case as Northflank's own examples do.
        STAGES = %w[Development Staging Production].freeze
        RUN_LIMIT = 20
        History = Capabilities::History
        # A run's status (ListWorkflowrunsResult, ListReleaseflowrunsResult) in Firefight's words. A run waiting on an
        # approval or another run is still going.
        RUN_STATUSES = {
          "pending" => History::QUEUED, "queued" => History::QUEUED, "waiting" => History::QUEUED, "running" => History::RUNNING,
          "retrying" => History::RUNNING, "async_wait" => History::RUNNING, "approval_wait" => History::RUNNING,
          "aborting" => History::RUNNING, "success" => History::SUCCEEDED, "failure" => History::FAILED,
          "aborted" => History::CANCELLED, "skipped" => History::CANCELLED
        }.freeze
        # A node's status (response.status). A skipped node is over without failing, so it counts as done, and says so.
        NODE_STATUSES = {
          "waiting" => History::QUEUED, "retrying" => History::RUNNING, "async_wait" => History::RUNNING,
          "approval_wait" => History::RUNNING, "aborting" => History::RUNNING, "success" => History::SUCCEEDED,
          "skipped" => History::SUCCEEDED, "failure" => History::FAILED, "invalid" => History::FAILED, "aborted" => History::CANCELLED
        }.freeze
        WAITING_WORDS = { "approval_wait" => "waiting for an approval", "async_wait" => "waiting on what it started", "skipped" => "skipped" }.freeze
        # Nodes that act on a service, job or addon, named by their ref while it is not resolved yet.
        TARGETED = %w[Build JobRun Release AddonBackup AddonImport].freeze
        # Nodes that only hold other nodes.
        CONTAINERS = %w[Workflow LoopWorkflow].freeze
        NODE_WORDS = {
          "Build" => "Build", "JobRun" => "Run job", "Release" => "Release", "Approval" => "Approval", "Condition" => "Wait for",
          "Action" => "Action", "Message" => "Message", "AddonBackup" => "Back up", "AddonImport" => "Import", "RunTemplate" => "Run template",
          "RolloutStrategy" => "Rollout", "SecretInheritance" => "Secrets", "LoopData" => "Loop"
        }.freeze
        REFERENCE = "${".freeze
        PIPELINES_PERMISSION = "Its role needs to read pipelines (Project, Pipelines, General, Read).".freeze
        WORKFLOWS_PERMISSION = "Its role needs to read workflows (Project, Workflows, General, Read).".freeze

        def self.included(pack)
          pack.tool WORKFLOW_RUNS,
                    summary: "Lists a workflow's recent runs and how each step went.",
                    description: "A Northflank workflow's recent runs, newest first, each with its status, when it started and finished and how " \
                                 "long it took, and how long finished runs usually take. Name a run to read it with each node, such as a " \
                                 "build, a release or a job run, how each went, the error a failed one gave and its retries",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "workflow" => { "type" => "string", "description" => "The workflow, by name or id" },
                        "name" => { "type" => "string", "description" => "Only runs whose workflow's name contains this (optional)" },
                        "run" => { "type" => "string", "description" => "Only this run, by its id, with each of its nodes (optional)" },
                        "limit" => { "type" => "integer", "description" => "At most this many runs (optional, #{RUN_LIMIT})" }
                      },
                      "required" => [ "workflow" ]
                    },
                    read_only: true

          pack.tool RELEASE_FLOW_RUNS,
                    summary: "Lists a pipeline stage's release flow runs and how each step went.",
                    description: "The recent runs of the release flow of one stage of a Northflank pipeline, newest first, each with its " \
                                 "status, when it started and finished and how long it took, and how long finished runs usually take. Name a " \
                                 "run to read it with each node, how each went, the error a failed one gave and its retries",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "pipeline" => { "type" => "string", "description" => "The pipeline, by name or id" },
                        "stage" => { "type" => "string", "enum" => STAGES, "description" => "The stage whose release flow ran" },
                        "name" => { "type" => "string", "description" => "Only runs whose release flow's name contains this (optional)" },
                        "run" => { "type" => "string", "description" => "Only this run, by its id, with each of its nodes (optional)" },
                        "limit" => { "type" => "integer", "description" => "At most this many runs (optional, #{RUN_LIMIT})" }
                      },
                      "required" => %w[pipeline stage]
                    },
                    read_only: true
        end

        def workflow_runs(environment_row:, arguments:)
          project = project_of(environment_row)
          workflow = workflow_named(environment_row, project, arguments["workflow"])
          name = workflow["name"].presence || workflow["id"]
          what = "workflow #{name}"
          link = project_link(environment_row)
          if arguments["run"].present?
            run = api(environment_row).workflow_run(project, workflow["id"], run_id(arguments))
            return History.result([ release_run(run, name).with(parts: parts_of(run)) ], what: what, link: link)
          end

          runs = api(environment_row).workflow_runs(project, workflow["id"], limit: limit(arguments, RUN_LIMIT))
          History.result(runs.map { |run| release_run(run, name) }, what: what, link: link, name: arguments["name"], limit: limit(arguments, RUN_LIMIT))
        end

        def release_flow_runs(environment_row:, arguments:)
          project = project_of(environment_row)
          pipeline = pipeline_named(environment_row, project, arguments["pipeline"])
          stage = stage_of(arguments["stage"])
          name = release_flow_name(pipeline, stage)
          link = project_link(environment_row)
          if arguments["run"].present?
            run = api(environment_row).release_flow_run(project, pipeline["id"], stage.downcase, run_id(arguments))
            return History.result([ release_run(run, name).with(parts: parts_of(run)) ], what: "release flow #{name}", link: link)
          end

          runs = begin
            api(environment_row).release_flow_runs(project, pipeline["id"], stage.downcase, limit: limit(arguments, RUN_LIMIT))
          rescue NorthflankApi::NotFound
            fail! "#{pipeline['name'].presence || pipeline['id']} has no release flow for #{stage}. Each stage that releases has its own."
          end
          History.result(runs.map { |run| release_run(run, name) }, what: "release flow #{name}", link: link, name: arguments["name"], limit: limit(arguments, RUN_LIMIT))
        end

        # The pipeline's own name and the stage, which is how Northflank's dashboard heads a release flow.
        def release_flow_name(pipeline, stage) = "#{pipeline['name'].presence || pipeline['id']} #{stage}"

        # A run as the list or the details give it, named by what ran it so a watch's name finds it, with its own name and
        # description beside the status words a person needs, such as waiting for an approval. Its own name, such as
        # release-v0-0-29, is its title, so a watch given that name follows exactly that run.
        def release_run(run, name)
          status = run["status"].to_s.downcase
          detail = [ run["name"].presence, run["description"].presence, WAITING_WORDS[status] ].compact.join(", ").presence
          History::Run.new(
            id: run["id"].to_s, name: name, title: run["name"].presence, status: History.status(status, RUN_STATUSES),
            started_at: Telemetry.parse_time(run["startedAt"] || run["createdAt"]),
            finished_at: (Telemetry.parse_time(run["concludedAt"] || run["updatedAt"]) if run["concluded"]), detail: detail
          )
        end

        # Each node that does something, in the order the run holds them, as a part with how it went, the error it gave,
        # its retries and how to read its log. Two nodes of one name are told apart by their refs.
        def parts_of(run)
          nodes = nodes_in(run["spec"])
          names = nodes.map { |node| node_name(node) }
          nodes.each_with_index.map do |node, index|
            name = names.count(names[index]) > 1 && node["ref"].present? ? "#{names[index]} (#{node['ref']})" : names[index]
            node_part(node, name, index)
          end
        end

        def nodes_in(node, found = [])
          case node
          when Array then node.each { |each| nodes_in(each, found) }
          when Hash
            return found unless node["kind"].is_a?(String)

            if CONTAINERS.include?(node["kind"])
              nodes_in(node.dig("spec", "steps"), found) if node["spec"].is_a?(Hash)
            else
              found << node
            end
          end
          found
        end

        def node_name(node)
          spec = node["spec"].is_a?(Hash) ? node["spec"] : {}
          target = [ node.dig("response", "data", "nfObjectId"), spec["id"], spec.dig("target", "id"), spec["jobId"], spec["name"] ].find { |each| literal?(each) }
          word = NODE_WORDS.fetch(node["kind"], node["kind"].underscore.humanize)
          return "#{word} #{target}" if target
          return word unless literal?(node["ref"]) && NODE_WORDS.key?(node["kind"]) && TARGETED.include?(node["kind"])

          "#{word} (#{node['ref']})"
        end

        def node_part(node, name, index)
          response = node["response"].is_a?(Hash) ? node["response"] : {}
          status = response["status"].to_s.downcase
          started = epoch_time(response["startTime"])
          finished = epoch_time(response["endTime"])
          retries = response["retries"].to_h
          tries = "attempt #{retries['attempts']} of #{retries['maxAttempts']}" if retries["attempts"].to_i > 1
          error = response.dig("error", "message").presence
          History::Part.new(
            id: node["ref"].presence || index.to_s, name: name, status: status.empty? ? History::QUEUED : History.status(status, NODE_STATUSES),
            started_at: started, finished_at: (finished if started), detail: [ error, tries, WAITING_WORDS[status] ].compact.join(", ").presence,
            log: node_log(node, started, finished)
          )
        end

        # How a node's log is read: a build's own build log, a job run's own logs, and a release's service or job over the
        # time it ran. nil for a node that logs nothing of its own, or one whose target is a reference not yet resolved.
        def node_log(node, started, finished)
          spec = node["spec"].is_a?(Hash) ? node["spec"] : {}
          data = node.dig("response", "data").is_a?(Hash) ? node.dig("response", "data") : {}
          window = { "start" => started&.utc&.iso8601, "end" => (finished || (Time.current if started))&.utc&.iso8601 }.compact
          case node["kind"]
          when "Build"
            target = [ data["nfObjectId"], spec["id"] ].find { |each| literal?(each) }
            target && log_handle(BUILD_LOGS, { "resource" => target, "build" => (data["id"] if literal?(data["id"])) }.compact.merge(window))
          when "JobRun"
            job = spec["jobId"] if literal?(spec["jobId"])
            job && log_handle(SEARCH_LOGS, { "resource" => job, "run" => (data["id"] if literal?(data["id"])) }.compact.merge(window))
          when "Release"
            target = spec.dig("target", "id")
            literal?(target) ? log_handle(SEARCH_LOGS, { "resource" => target }.merge(window)) : nil
          end
        end

        def log_handle(tool, arguments) = { History::LOG_TOOL => tool, History::LOG_ARGUMENTS => arguments }

        def literal?(value) = value.is_a?(String) && value.present? && !value.include?(REFERENCE)

        # Northflank writes a node's times as Unix seconds, read as milliseconds when they are that large.
        def epoch_time(value)
          number = value.to_i
          return unless number.positive?

          Time.zone.at(number > 100_000_000_000 ? number / 1000.0 : number).utc
        end

        def run_id(arguments)
          id = arguments["run"].to_s.strip.delete_prefix("#")
          fail! "run must be the run's id, as the list of runs gives it." unless id.match?(PROJECT_PATH) && !id.include?("/")

          id
        end

        def stage_of(given)
          stage = STAGES.find { |each| each.casecmp?(given.to_s.strip) }
          stage || fail!("stage must be one of #{STAGES.join(', ')}.")
        end

        def workflow_named(environment_row, project, reference)
          fail! "Say which workflow, by name or id." if reference.to_s.strip.empty?

          listed = api(environment_row).workflows(project)
          found = Named.find(listed.items, reference, id: "id", name: "name", provider: PROVIDER, connection: environment_row)
          found || by_id_past_cut(listed, reference, "workflow") { api(environment_row).workflow(project, reference.to_s.strip) }
        end

        def pipeline_named(environment_row, project, reference)
          fail! "Say which pipeline, by name or id." if reference.to_s.strip.empty?

          listed = api(environment_row).pipelines(project)
          found = Named.find(listed.items, reference, id: "id", name: "name", provider: PROVIDER, connection: environment_row)
          found || by_id_past_cut(listed, reference, "pipeline") { api(environment_row).pipeline(project, reference.to_s.strip).merge("id" => reference.to_s.strip) }
        end

        # One the listing did not reach, read by its id, or the refusal that says why it was not found.
        def by_id_past_cut(listed, reference, what)
          fail! "No #{what} called #{reference} in this project." if listed.complete

          found = yield
          found.presence || fail!("Only the first #{listed.items.size} #{what.pluralize} were read, and none is called #{reference}. Name it by its id.")
        rescue NorthflankApi::NotFound
          fail! "Only the first #{listed.items.size} #{what.pluralize} were read, and none is called #{reference}. Name it by its id."
        end

        # The project's workflows and pipelines with each stage's release flow, and what each releases, read into the map.
        # A list the token may not read is a gap naming the permission, so the rest of the map is read as before.
        def map_releases(api, project, mapping, kinds_of, gaps)
          begin
            workflows = api.workflows(project)
            workflows.items.each { |listed| mapping.workflow(listed, targets_of(workflow_details(api, project, listed, gaps), kinds_of)) }
            gaps << cut_short("workflows", [ ResourceMap::KIND_WORKFLOW ]) if workflows.incomplete?
          rescue NorthflankApi::Error => error
            gaps << ResourceMap::Gap.new(text: Sentence.all(Sentence.join("Workflows could not be read", error), WORKFLOWS_PERMISSION), kinds: [ ResourceMap::KIND_WORKFLOW ])
          end
          begin
            pipelines = api.pipelines(project)
            pipelines.items.each { |listed| map_pipeline(api, project, listed, mapping, kinds_of) }
            gaps << cut_short("pipelines", [ ResourceMap::KIND_PIPELINE, ResourceMap::KIND_RELEASE_FLOW ]) if pipelines.incomplete?
          rescue NorthflankApi::RateLimited
            raise
          rescue NorthflankApi::Error => error
            gaps << ResourceMap::Gap.new(text: Sentence.all(Sentence.join("Pipelines could not be read", error), PIPELINES_PERMISSION),
                                         kinds: [ ResourceMap::KIND_PIPELINE, ResourceMap::KIND_RELEASE_FLOW ])
          end
        end

        # A workflow's definition, which names what it builds, runs and releases. One that cannot be read keeps the workflow
        # on the map without new links, and its gap keeps the links it had.
        def workflow_details(api, project, listed, gaps)
          api.workflow(project, listed["id"])
        rescue NorthflankApi::RateLimited
          raise
        rescue NorthflankApi::Error => error
          gaps << ResourceMap::Gap.new(text: Sentence.join("What workflow #{listed['name'] || listed['id']} releases could not be read", error), kinds: [ ResourceMap::KIND_WORKFLOW ])
          {}
        end

        # A pipeline, and each stage that holds something with the release flow Northflank has for it, which releases what
        # the stage holds. A stage with no release flow is not found.
        def map_pipeline(api, project, listed, mapping, kinds_of)
          details = api.pipeline(project, listed["id"])
          pipeline = mapping.pipeline(listed.merge(details.slice("name", "description")))
          Array(details["nfObjects"]).group_by { |object| object["stage"] }.each do |stage, objects|
            next unless STAGES.include?(stage)

            flow = begin
              api.release_flow(project, listed["id"], stage.downcase)
            rescue NorthflankApi::NotFound
              nil
            end
            next if flow.blank?

            released = objects.filter_map { |object| kinds_of.call(object["type"], object["id"]) }
            mapping.release_flow("#{listed['id']}/#{stage.downcase}", release_flow_name(listed.merge(details.slice("name")), stage), pipeline, released)
          end
        end

        # What a workflow's nodes name by a literal id, each as the kind it is on the map.
        def targets_of(definition, kinds_of)
          nodes_in(definition["spec"]).filter_map do |node|
            spec = node["spec"].is_a?(Hash) ? node["spec"] : {}
            case node["kind"]
            when "Build" then kinds_of.call(spec["type"], spec["id"]) if literal?(spec["id"])
            when "Release" then kinds_of.call(spec.dig("target", "type"), spec.dig("target", "id")) if literal?(spec.dig("target", "id"))
            when "JobRun" then kinds_of.call("job", spec["jobId"]) if literal?(spec["jobId"])
            end
          end.uniq
        end

        # Only the workflow, pipeline or release flow a notification named, or every one of that kind in the project when it
        # named none. Gone only for Northflank's own not found of the one named.
        def release_refresh(environment_row, scope)
          project = project_of(environment_row)
          api = api(environment_row)
          account = account_on_map(environment_row, project)
          return unless account

          mapping = MapReading.new(account) { |_kind, _id| nil }
          kinds_of = map_kinds(environment_row, account)
          gaps = []
          case scope.kind
          when ResourceMap::KIND_WORKFLOW
            return map_releases_of_kind(api, project, mapping, kinds_of, gaps, workflows: true) unless scope.external_id

            listed = api.workflow(project, scope.external_id)
            return released_gone(account, scope) if listed.blank?

            mapping.workflow(listed, targets_of(listed, kinds_of))
          else
            return map_releases_of_kind(api, project, mapping, kinds_of, gaps, workflows: false) unless scope.external_id

            pipeline_id = scope.external_id.split("/").first
            details = api.pipeline(project, pipeline_id)
            return released_gone(account, scope) if details.blank?

            map_pipeline(api, project, details.merge("id" => pipeline_id), mapping, kinds_of)
          end
          ResourceMap::Snapshot.new(resources: mapping.resources, links: mapping.links, gaps: gaps)
        rescue NorthflankApi::NotFound
          released_gone(account, scope)
        end

        def map_releases_of_kind(api, project, mapping, kinds_of, gaps, workflows:)
          if workflows
            api.workflows(project).items.each { |listed| mapping.workflow(listed, targets_of(workflow_details(api, project, listed, gaps), kinds_of)) }
          else
            api.pipelines(project).items.each { |listed| map_pipeline(api, project, listed, mapping, kinds_of) }
          end
          ResourceMap::Snapshot.new(resources: mapping.resources, links: mapping.links, gaps: gaps)
        end

        # A pipeline gone takes its release flows with it, and a workflow is gone alone.
        def released_gone(account, scope)
          return unless account && scope.external_id

          keys = if scope.kind == ResourceMap::KIND_WORKFLOW
            [ [ PROVIDER_KEY, account, ResourceMap::KIND_WORKFLOW, scope.external_id ] ]
          else
            pipeline_id = scope.external_id.split("/").first
            [ [ PROVIDER_KEY, account, ResourceMap::KIND_PIPELINE, pipeline_id ],
              *STAGES.map { |stage| [ PROVIDER_KEY, account, ResourceMap::KIND_RELEASE_FLOW, "#{pipeline_id}/#{stage.downcase}" ] } ]
          end
          ResourceMap::Snapshot.new(resources: [], gone: keys)
        end

        # What the map already holds of the project, for a re-read that has no service to read the team from.
        def map_kinds(environment_row, account)
          held = ResourceMap::Resource.present.where(integration_environment: environment_row, provider: PROVIDER_KEY, account: account).pluck(:external_id, :kind)
          by_id = held.group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
          kinds_lookup { |id, wanted| (by_id[id.to_s] & wanted).first }
        end

        # Answers what a node or a stage names, as the kind it has on the map: a service that only builds is a build
        # service, an addon a database.
        def kinds_lookup(&found)
          lambda do |type, id|
            return unless literal?(id)

            wanted = case type.to_s
            when "service" then [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_BUILD_SERVICE ]
            when "job" then [ ResourceMap::KIND_JOB ]
            when "addon" then [ ResourceMap::KIND_DATABASE ]
            else []
            end
            kind = found.call(id, wanted)
            [ kind, id.to_s ] if kind
          end
        end

        def account_on_map(environment_row, project)
          ResourceMap::Resource.present.where(integration_environment: environment_row, provider: PROVIDER_KEY)
                               .where("account = :project OR account LIKE :within", project: project, within: "%/#{ResourceMap::Resource.sanitize_sql_like(project)}")
                               .pick(:account)
        end
      end
    end
  end
end
