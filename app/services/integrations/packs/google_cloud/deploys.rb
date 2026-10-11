module Integrations
  module Packs
    class GoogleCloud < NativePack
      # Cloud Deploy's delivery pipelines and their stages, as runs Firefight follows and as resources on the map, from the
      # Cloud Deploy API v1 (DeliveryPipeline, Target, Release, Rollout, Phase, Job and JobRun). A pipeline promotes each
      # release through its stages in order, one target a stage, and each promotion is a rollout: phases of jobs (predeploy,
      # deploy, verify, analysis, postdeploy) that each run as a Cloud Build build. A rollout is named by its release and
      # its own id, since a rollout's id is unique only within its release.
      module Deploys
        LIST_ROLLOUTS = "list_rollouts".freeze
        ROLLBACK_TARGET = "rollback_target".freeze
        CANCEL_ROLLOUT = "cancel_rollout".freeze
        ROLLOUT_LIMIT = 20
        # How many releases a stage's rollouts are looked for in, since a later stage has a rollout of fewer of them.
        RELEASE_SCAN = 30
        History = Capabilities::History
        # Rollout.state in Firefight's words. A rollout waiting on an approval is still going, and one halted because
        # another failed did not finish its work.
        ROLLOUT_STATES = {
          "pending" => History::QUEUED, "pending_release" => History::QUEUED, "pending_approval" => History::RUNNING,
          "in_progress" => History::RUNNING, "cancelling" => History::RUNNING, "succeeded" => History::SUCCEEDED,
          "failed" => History::FAILED, "halted" => History::FAILED, "approval_rejected" => History::CANCELLED,
          "cancelled" => History::CANCELLED
        }.freeze
        # Job.state. A job switched off or skipped is over without failing, and one whose failure was ignored let the
        # rollout go on, so each counts as done and says so.
        JOB_STATES = {
          "pending" => History::QUEUED, "in_progress" => History::RUNNING, "succeeded" => History::SUCCEEDED,
          "disabled" => History::SUCCEEDED, "skipped" => History::SUCCEEDED, "ignored" => History::SUCCEEDED,
          "failed" => History::FAILED, "aborted" => History::CANCELLED
        }.freeze
        STATE_WORDS = {
          "PENDING_APPROVAL" => "waiting for an approval", "PENDING_RELEASE" => "waiting for its release to render", "HALTED" => "halted",
          "APPROVAL_REJECTED" => "its approval was rejected", "CANCELLING" => "being cancelled", "DISABLED" => "switched off",
          "SKIPPED" => "skipped", "IGNORED" => "failed, then ignored"
        }.freeze
        # A rollout that has not finished, which cancel stops.
        IN_FLIGHT = %w[PENDING PENDING_RELEASE PENDING_APPROVAL IN_PROGRESS].freeze
        # A phase's jobs in the order they run (DeploymentJobs).
        PHASE_JOBS = %w[predeployJob deployJob verifyJob analysisJob postdeployJob].freeze
        # Where a JobRun keeps the build that ran it and why it failed, by kind of job.
        JOB_RUN_KINDS = %w[deployJobRun verifyJobRun predeployJobRun postdeployJobRun analysisJobRun].freeze
        # Labels Cloud Deploy adds to what it renders, so a Cloud Run service or job it deployed names its pipeline and
        # target (Cloud Deploy, Labels and annotations).
        PIPELINE_LABEL = "deploy.cloud.google.com/delivery-pipeline-id".freeze
        TARGET_LABEL = "deploy.cloud.google.com/target-id".freeze
        LOCATION_LABEL = "deploy.cloud.google.com/location".freeze
        PROJECT_LABEL = "deploy.cloud.google.com/project-id".freeze
        # A project that never turned Cloud Deploy on has no pipelines, which Google answers as the API being off.
        API_OFF = /SERVICE_DISABLED|has not been used in project|it is disabled/
        BUILD_LOG = "build".freeze
        # A rollout's id as Cloud Deploy allows it (RollbackTargetRequest.rolloutId).
        ROLLBACK_PREFIX = "firefight-rollback".freeze
        RUN_FORMAT = "run must be the rollout's release and id, release/rollout, as list_rollouts shows it.".freeze
        STAGE = { "type" => "string", "description" => "A Cloud Deploy pipeline stage, by its name (the pipeline and target) or id, as list_resources shows it" }.freeze

        def self.included(pack)
          pack.tool LIST_ROLLOUTS,
                    description: "The recent rollouts of a Cloud Deploy delivery pipeline, or of one of its stages, newest first, each with " \
                                 "its release, status, when it started and finished, how long it took, why it failed, and how long finished " \
                                 "rollouts usually take. Name a rollout to read it with each phase's jobs (predeploy, deploy, verify, " \
                                 "postdeploy), how each went and why a failed one failed",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "resource" => { "type" => "string", "description" => "A Cloud Deploy delivery pipeline or one of its stages, by name or id, as list_resources shows it" },
                        "name" => { "type" => "string", "description" => "Only rollouts to stages whose name contains this, such as a target (optional)" },
                        "run" => { "type" => "string", "description" => "Only this rollout, as release/rollout, with each of its jobs (optional)" },
                        "limit" => { "type" => "integer", "description" => "At most this many rollouts (optional, #{ROLLOUT_LIMIT})" }
                      },
                      "required" => [ "resource" ]
                    },
                    read_only: true

          pack.tool ROLLBACK_TARGET,
                    description: "Roll one stage of a Cloud Deploy pipeline back: Cloud Deploy makes a new rollout of an earlier release to " \
                                 "the stage's target, the release named or the last one that succeeded there. list_rollouts shows the " \
                                 "releases each stage ran. Undo by promoting the release it ran before to the stage again",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "resource" => STAGE,
                        "release" => { "type" => "string", "description" => "The release to go back to, by its id (optional, the last one that succeeded on the stage)" }
                      },
                      "required" => [ "resource" ]
                    },
                    read_only: false

          pack.tool CANCEL_ROLLOUT,
                    description: "Stop a Cloud Deploy rollout that has not finished, such as one waiting for an approval or deploying. What it " \
                                 "already deployed stays, so roll the stage back to undo that",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "resource" => { "type" => "string", "description" => "The Cloud Deploy delivery pipeline or stage the rollout is in, by name or id" },
                        "run" => { "type" => "string", "description" => "The rollout, as release/rollout, as list_rollouts shows it" }
                      },
                      "required" => %w[resource run]
                    },
                    read_only: false
        end

        def list_rollouts(environment_row:, arguments:)
          target = deploy_target(environment_row, arguments["resource"])
          what = "the rollouts of #{display_name(target)}"
          link = page_link(environment_row, target.project, target.type)
          if arguments["run"].present?
            release, rollout = rollout_of(environment_row, target, arguments["run"])
            job_runs = api(environment_row).job_runs(target.project, target.location, target.pipeline, release, short(rollout["name"]))
            run = rollout_run(rollout, target, release).with(parts: rollout_parts(target, rollout, release, job_runs))
            return History.result([ run ], what: what, link: link)
          end

          limit = Capabilities::Answers.limit(arguments, ROLLOUT_LIMIT)
          runs = newest_rollouts(environment_row, target, limit).map { |release, rollout| rollout_run(rollout, target, release) }
          History.result(runs, what: what, link: link, name: arguments["name"], limit: limit)
        end

        def rollback_target(environment_row:, arguments:)
          target = deploy_target(environment_row, arguments["resource"])
          fail!("#{display_name(target)} is a whole pipeline. Name the stage to roll back, such as #{target.pipeline} prod.") unless target.target_id

          api = api(environment_row)
          pipeline = api.delivery_pipeline(target.project, target.location, target.pipeline)
          fail!("#{target.pipeline} is suspended, so Cloud Deploy makes no rollout on it. Resume it first.") if pipeline["suspended"]

          wanted = arguments["release"].to_s.strip.split("/").last.presence
          if wanted
            begin
              api.release(target.project, target.location, target.pipeline, wanted)
            rescue GoogleCloudApi::NotFound
              fail!("#{target.pipeline} has no release called #{wanted}. list_rollouts shows the releases each stage ran.")
            end
          end
          before = newest_rollouts(environment_row, target, 1).first&.first
          id = "#{ROLLBACK_PREFIX}-#{SecureRandom.hex(4)}"
          answer = api.rollback_target(target.project, target.location, target.pipeline, { "targetId" => target.target_id, "rolloutId" => id, "releaseId" => wanted }.compact)
          made = answer.dig("rollbackConfig", "rollout", "name").to_s.split("/releases/").last.to_s.split("/rollouts/").first.presence
          to = wanted || made || "the last release that succeeded there"
          Telemetry.result("Cloud Deploy is rolling #{display_name(target)} back to #{to} as rollout #{id}. " \
                           "#{before ? "Before, it ran release #{before}, so to undo, promote #{before} to #{target.target_id} again." : 'It had no rollout before to promote again.'}",
                           link: page_link(environment_row, target.project, target.type))
        end

        def cancel_rollout(environment_row:, arguments:)
          target = deploy_target(environment_row, arguments["resource"])
          release, rollout = rollout_of(environment_row, target, arguments["run"])
          name = short(rollout["name"])
          unless IN_FLIGHT.include?(rollout["state"])
            fail!("Rollout #{name} of release #{release} has already ended (#{rollout['state'].to_s.downcase.tr('_', ' ')}), so there is nothing to cancel.")
          end

          api(environment_row).cancel_rollout(target.project, target.location, target.pipeline, release, name)
          Telemetry.result("Cloud Deploy is cancelling rollout #{name} of release #{release} to #{rollout['targetId']}. What it already deployed stays, " \
                           "so roll #{target.pipeline} #{rollout['targetId']} back to undo that.", link: page_link(environment_row, target.project, target.type))
        end

        private

        # The rollout a call names, read by its release and its own id, however old.
        def rollout_of(environment_row, target, asked)
          release, rollout = rollout_reference(asked)
          found = api(environment_row).rollout(target.project, target.location, target.pipeline, release, rollout)
          if target.target_id && found["targetId"] != target.target_id
            fail!("Rollout #{rollout} of release #{release} went to #{found['targetId']}, not #{target.target_id}. Name that stage instead.")
          end
          [ release, found ]
        rescue GoogleCloudApi::NotFound
          fail!("#{target.pipeline} has no rollout #{rollout} in release #{release}. list_rollouts shows them.")
        end

        def deploy_target(environment_row, asked)
          target = find(environment_row, asked)
          fail!("#{target.name} is a #{target.type}. This works on a Cloud Deploy delivery pipeline or one of its stages.") unless target.deploy?

          target
        end

        def display_name(target) = target.target_id ? "#{target.pipeline} #{target.target_id}" : target.pipeline

        # A rollout's run with one job after it, release/rollout/phase/job, split into the rollout and the job.
        def rollout_and_job(asked)
          parts = asked.to_s.strip.split("/")
          return [ asked.to_s.strip.presence, nil ] unless parts.size == 4

          [ parts.first(2).join("/"), parts.last(2).join("/") ]
        end

        def rollout_reference(asked)
          text = asked.to_s.strip
          found = text.match(%r{releases/(?<release>[^/]+)/rollouts/(?<rollout>[^/]+)\z}) || text.match(%r{\A(?<release>[a-z0-9-]+)/(?<rollout>[a-z0-9-]+)\z})
          fail!(RUN_FORMAT) unless found

          [ found[:release], found[:rollout] ]
        end

        # The newest rollouts, as [release, rollout], from the newest releases down, only the stage's for a stage.
        def newest_rollouts(environment_row, target, limit)
          api = api(environment_row)
          releases = api.releases(target.project, target.location, target.pipeline, page_size: target.target_id ? [ RELEASE_SCAN, limit ].max : limit)
          found = []
          releases.sort_by { |release| release["createTime"].to_s }.reverse_each do |release|
            name = short(release["name"])
            rollouts = api.rollouts(target.project, target.location, target.pipeline, name)
            rollouts = rollouts.select { |rollout| rollout["targetId"] == target.target_id } if target.target_id
            found.concat(rollouts.map { |rollout| [ name, rollout ] })
            break if found.size >= limit
          end
          found.sort_by { |_, rollout| rollout["createTime"].to_s }.reverse.first(limit)
        end

        # A rollout as every run history reads it, named by its stage, from when it started deploying (or was made, while it
        # waits) to when it finished.
        def rollout_run(rollout, target, release)
          status = History.status(rollout["state"], ROLLOUT_STATES)
          History::Run.new(
            id: "#{release}/#{short(rollout['name'])}", name: "#{target.pipeline} #{rollout['targetId']}", status: status,
            started_at: Capabilities::RunHistory.time(rollout["deployStartTime"] || rollout["enqueueTime"] || rollout["createTime"]),
            finished_at: (Capabilities::RunHistory.time(rollout["deployEndTime"]) if History::FINISHED.include?(status)),
            detail: rollout_detail(rollout, release)
          )
        end

        def rollout_detail(rollout, release)
          cause = rollout["deployFailureCause"].to_s
          [
            "release #{release}", STATE_WORDS[rollout["state"]],
            ("rollback of #{short(rollout['rollbackOfRollout'])}" if rollout["rollbackOfRollout"].present?),
            rollout["failureReason"].presence, (cause.downcase.tr("_", " ") if cause.present? && cause != "FAILURE_CAUSE_UNSPECIFIED")
          ].compact.join(", ")
        end

        # Each job of each phase, in the order they run, with what its job run says: when it ran, why it failed, and its
        # Cloud Build build, whose log is the job's.
        def rollout_parts(target, rollout, release, job_runs)
          by_name = job_runs.index_by { |run| run["name"] }
          Array(rollout["phases"]).flat_map do |phase|
            jobs = PHASE_JOBS.filter_map { |field| phase.dig("deploymentJobs", field) }
            jobs += %w[createRolloutJobs advanceRolloutJobs].flat_map { |field| Array(phase.dig("childRolloutJobs", field)) }
            jobs.map { |job| job_part(target, rollout, release, phase, job, by_name[job["jobRun"]]) }
          end
        end

        def job_part(target, rollout, release, phase, job, run)
          kind = run && JOB_RUN_KINDS.find { |each| run[each].is_a?(Hash) }
          ran = kind ? run[kind] : {}
          status = job["state"].blank? ? History::QUEUED : History.status(job["state"], JOB_STATES)
          started = Capabilities::RunHistory.time(run&.dig("startTime"))
          finished = Capabilities::RunHistory.time(run&.dig("endTime")) if History::FINISHED.include?(status)
          cause = ran["failureCause"].to_s
          detail = [ ran["failureMessage"].presence, (cause.downcase.tr("_", " ") if cause.present? && cause != "FAILURE_CAUSE_UNSPECIFIED"),
                     STATE_WORDS[job["state"]], job["skipMessage"].presence ].compact.uniq.join(", ").presence
          id = "#{phase['id']}/#{job['id']}"
          log = if ran["build"].present?
            { History::LOG_TOOL => "search_logs",
              History::LOG_ARGUMENTS => { "resource" => target.id, "run" => "#{release}/#{short(rollout['name'])}/#{id}",
                                          "start" => started&.utc&.iso8601, "end" => (finished || (Time.current if started))&.utc&.iso8601 }.compact }
          end
          History::Part.new(id: id, name: "#{phase['id']} #{job['id']}", status: status, started_at: started, finished_at: finished, detail: detail, log: log)
        end

        # The log of a rollout's jobs, or one job's, which is what the Cloud Build builds that ran them printed. With no
        # rollout named, the newest one.
        def rollout_logs(environment_row, target, arguments)
          stream = arguments["stream"].presence || STREAM_APP
          unless [ STREAM_APP, BUILD_LOG ].include?(stream)
            fail!("A Cloud Deploy rollout's log is what its jobs printed, so leave stream out.")
          end

          asked, step = rollout_and_job(arguments["run"])
          release, rollout = if asked
            rollout_of(environment_row, target, asked)
          else
            newest_rollouts(environment_row, target, 1).first || fail!("#{display_name(target)} has no rollouts yet.")
          end
          name = short(rollout["name"])
          runs = api(environment_row).job_runs(target.project, target.location, target.pipeline, release, name)
          runs = runs.select { |run| "#{run['phaseId']}/#{run['jobId']}" == step } if step
          builds = runs.filter_map { |run| JOB_RUN_KINDS.filter_map { |kind| run.dig(kind, "build") }.first }
          if builds.empty?
            fail!("#{step ? "Job #{step} of rollout" : 'Rollout'} #{name} of release #{release} has run no build yet, so it has no log. " \
                  "list_rollouts with its run says how each job went.")
          end

          scope = [ "resource.type=#{quote(BUILD_LOG)}", "(#{builds.map { |build| "resource.labels.build_id=#{quote(short(build))}" }.join(' OR ')})" ]
          started, ended = run_window(arguments) { rollout }
          read_lines(environment_row, target, scope, started, ended, arguments, [ "rollout #{release}/#{name}", step && "job #{step}" ].compact,
                     page_link(environment_row, target.project, target.type))
        end

        # The project's delivery pipelines and each one's stages in every region Cloud Deploy serves it in. A project that
        # never turned the API on has none.
        def deploy_items(api, project)
          locations = api.deploy_locations(project)
          complete = locations.complete
          found = locations.items.filter_map { |location| location["locationId"] }.flat_map do |location|
            pipelines = api.delivery_pipelines(project, location)
            complete &&= pipelines.complete
            next [] if pipelines.items.empty?

            targets = region_targets(api, project, location)
            pipelines.items.flat_map { |pipeline| pipeline_items(pipeline, targets) }
          end
          [ found, complete ]
        rescue GoogleCloudApi::Forbidden => error
          raise unless error.message.match?(API_OFF)

          [ [], true ]
        end

        # A region's targets by id, which say where each stage releases to. One that cannot be read leaves that unsaid.
        def region_targets(api, project, location)
          api.deploy_targets(project, location).items.index_by { |target| target["targetId"].presence || short(target["name"]) }
        rescue Integrations::RateLimited
          raise
        rescue GoogleCloudApi::Error
          {}
        end

        # A pipeline and a stage for each target it promotes to, in order.
        def pipeline_items(pipeline, targets)
          found = Target.parse(pipeline["name"])
          return [] unless found

          stages = Array(pipeline.dig("serialPipeline", "stages"))
          ready = pipeline.dig("condition", "pipelineReadyCondition", "status")
          status = if pipeline["suspended"] then "paused"
          elsif ready == false then "degraded"
          elsif ready == true then "ready"
          end
          item = { type: TYPE_PIPELINE, id: pipeline["name"], name: found.name, location: found.location, status: status, hosts: [], source: pipeline,
                   details: { TYPE => TYPE_PIPELINE, "region" => found.location, "stages" => stages.map { |stage| stage["targetId"] }.join(", ").presence,
                              "suspended" => (true if pipeline["suspended"]), ResourceMap::TAGS => pipeline["labels"].presence }.compact }
          [ item, *stages.each_with_index.map { |stage, index| stage_item(found, stage, index, stages.size, targets[stage["targetId"]]) } ]
        end

        def stage_item(pipeline, stage, index, count, deploy_target)
          id = "#{pipeline.id}/targets/#{stage['targetId']}"
          { type: TYPE_STAGE, id: id, name: "#{pipeline.name} #{stage['targetId']}", location: pipeline.location, status: nil, hosts: [],
            source: { "pipeline" => pipeline.id },
            details: { TYPE => TYPE_STAGE, "region" => pipeline.location, "target" => stage["targetId"], "stage" => "#{index + 1} of #{count}",
                       "releases_to" => deploy_target && releases_to(deploy_target), "requires_approval" => (true if deploy_target&.dig("requireApproval")),
                       "strategy" => stage["strategy"]&.keys&.first, "profiles" => Array(stage["profiles"]).join(", ").presence }.compact }
        end

        # Where a target deploys (Target: run, gke, anthosCluster, multiTarget or customTarget).
        def releases_to(target)
          if target["run"] then "Cloud Run in #{target.dig('run', 'location').to_s.split('/').last}"
          elsif target["gke"] then "GKE cluster #{target.dig('gke', 'cluster').to_s.split('/').last}"
          elsif target["anthosCluster"] then "Anthos cluster #{target.dig('anthosCluster', 'membership').to_s.split('/').last}"
          elsif target["multiTarget"] then "targets #{Array(target.dig('multiTarget', 'targetIds')).join(', ')}"
          elsif target["customTarget"] then "a custom target"
          end
        end

        # What a resource read in the sweep links to beyond itself: a stage is part of its pipeline, and a Cloud Run service
        # or job Cloud Deploy released names the stage that released it in its labels.
        def release_links(key, item, reading)
          case item[:type]
          when TYPE_STAGE
            reading.links << ResourceMap::FoundLink.new(from: key, to: [ PROVIDER_KEY, key[1], ResourceMap::KIND_PIPELINE, item[:source]["pipeline"] ],
                                                        relation: ResourceMap::RELATION_PART_OF)
          when TYPE_RUN, TYPE_JOB
            job_links(key, item[:source], reading) if item[:type] == TYPE_JOB
            labels = item[:source]["labels"].to_h
            project, location, pipeline, stage = labels.values_at(PROJECT_LABEL, LOCATION_LABEL, PIPELINE_LABEL, TARGET_LABEL)
            if [ project, location, pipeline, stage ].all?(&:present?)
              stage_id = "projects/#{project}/locations/#{location}/deliveryPipelines/#{pipeline}/targets/#{stage}"
              reading.links << ResourceMap::FoundLink.new(from: key, to: [ PROVIDER_KEY, project, ResourceMap::KIND_RELEASE_FLOW, stage_id ],
                                                          relation: ResourceMap::RELATION_RELEASED_BY)
            end
          end
        end

        # One pipeline read again with its stages, a stage it no longer has gone, and the whole pipeline gone when Google
        # answers not found for it.
        def deploy_refresh(environment_row, project, target)
          api = api(environment_row)
          mapped = ResourceMap::Resource.present.where(integration_environment: environment_row, provider: PROVIDER_KEY, kind: ResourceMap::KIND_RELEASE_FLOW)
                                        .where("external_id LIKE ?", "#{ResourceMap::Resource.sanitize_sql_like(target.pipeline_id)}/targets/%").pluck(:external_id)
          pipeline = begin
            api.delivery_pipeline(project, target.location, target.pipeline)
          rescue GoogleCloudApi::NotFound
            gone = [ [ PROVIDER_KEY, project, ResourceMap::KIND_PIPELINE, target.pipeline_id ], *mapped.map { |id| [ PROVIDER_KEY, project, ResourceMap::KIND_RELEASE_FLOW, id ] } ]
            return ResourceMap::Snapshot.new(resources: [], gone: gone)
          end
          items = pipeline_items(pipeline, region_targets(api, project, target.location))
          reading = MapReading.new(environment_row.integration.workspace)
          items.each { |item| map_item(environment_row, project, item, reading) }
          kept = items.map { |item| item[:id] }
          ResourceMap::Snapshot.new(resources: reading.resources, links: reading.links, gaps: [],
                                    gone: (mapped - kept).map { |id| [ PROVIDER_KEY, project, ResourceMap::KIND_RELEASE_FLOW, id ] })
        end

        def pipeline_lines(environment_row, target)
          pipeline = api(environment_row).delivery_pipeline(target.project, target.location, target.pipeline)
          targets = region_targets(api(environment_row), target.project, target.location)
          stages = Array(pipeline.dig("serialPipeline", "stages")).map do |stage|
            deploy = targets[stage["targetId"]]
            [ stage["targetId"], (releases_to(deploy) if deploy), ("needs an approval" if deploy&.dig("requireApproval")),
              ("#{stage['strategy'].keys.first} strategy" if stage["strategy"].present?) ].compact.join(", ")
          end
          missing = Array(pipeline.dig("condition", "targetsPresentCondition", "missingTargets")).map { |name| short(name) }
          [
            "#{target.pipeline}, a Cloud Deploy delivery pipeline in #{target.location}#{', suspended' if pipeline['suspended']}",
            (pipeline["description"].presence),
            ("Stages, in the order a release is promoted:\n#{stages.map { |line| "- #{line}" }.join("\n")}" if stages.any?),
            ("Its stages name targets that do not exist: #{missing.join(', ')}." if missing.any?),
            (target.target_id ? "This is stage #{target.target_id}. list_rollouts shows its rollouts, and rollback_target rolls it back." : "list_rollouts shows its rollouts."),
            "Last changed #{pipeline['updateTime']}"
          ]
        end
      end
    end
  end
end
