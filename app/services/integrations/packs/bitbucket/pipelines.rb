module Integrations
  module Packs
    class Bitbucket
      # A repository's CI as Bitbucket Pipelines keeps it (the pipelines, steps, log, deployments and environments paths of
      # Bitbucket's OpenAPI description): its pipelines, their steps, a step's log, and how a branch and the environments
      # stand now. Bitbucket gives a pipeline no web address, so its page is the repository's pipelines/results/<build
      # number>, the address Bitbucket's own app serves.
      module Pipelines
        PIPELINE_LIMIT = 10
        MAX_PIPELINES = 50
        PIPELINE_CANDIDATES = 30
        STREAK = 10
        ENVIRONMENTS_SHOWN = 5
        FAILED = "FAILED".freeze
        ERROR = "ERROR".freeze
        FAILED_RESULTS = [ FAILED, ERROR ].freeze
        SUCCESSFUL = "SUCCESSFUL".freeze
        NEWEST_FIRST = "-created_on".freeze
        # The values Bitbucket's pipelines list filters status by.
        PIPELINE_STATUSES = %w[PARSING PENDING PAUSED HALTED BUILDING ERROR PASSED FAILED STOPPED UNKNOWN].freeze
        UUID_FORMAT = /\A\{?\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\}?\z/

        def self.included(pack)
          repo = pack::REPO_PARAM
          pipeline = { "type" => "string", "description" => "The pipeline's uuid, as pipelines or ci_status shows it" }
          pack.tool :pipelines,
                    description: "A repository's pipelines, newest first, with their outcome, branch, commit, what started them and their page",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo,
                      "branch" => { "type" => "string", "description" => "Only pipelines for this branch (optional)" },
                      "status" => { "type" => "string", "enum" => PIPELINE_STATUSES, "description" => "Only pipelines in this status, such as FAILED (optional)" },
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{PIPELINE_LIMIT}, at most #{MAX_PIPELINES})" }
                    }, %w[repo]),
                    read_only: true

          pack.tool :pipeline_steps,
                    description: "The steps of one pipeline, with each one's outcome and how long it took. Use job_log for a step's output",
                    params_schema: CodeHost::Code.object_schema({ "repo" => repo, "pipeline" => pipeline }, %w[repo pipeline]),
                    read_only: true

          pack.tool :job_log,
                    description: "The end of a pipeline step's log, where it says why it failed, filtered by text if asked. Without a step, the " \
                                 "newest failed step in the repository, on a branch when one is named, in the time asked when one is given",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo,
                      "pipeline" => pipeline.merge("description" => "The pipeline's uuid, with step (optional)"),
                      "step" => { "type" => "string", "description" => "The step's uuid, as pipeline_steps shows it (optional)" },
                      "branch" => { "type" => "string", "description" => "Only a step on this branch, when no step is named (optional)" },
                      **CodeHost::LOG_FILTER, **CodeHost::LOG_RANGE
                    }, %w[repo]),
                    read_only: true

          pack.tool :ci_status,
                    description: "How a repository's CI stands now: the latest pipeline on a branch (the main branch unless named) with its " \
                                 "failed steps, how the last pipelines went and since when it fails, and what each environment last deployed",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo, "branch" => { "type" => "string", "description" => "The branch (optional, the main branch)" }
                    }, %w[repo]),
                    read_only: true
        end

        def pipelines(environment_row:, arguments:)
          repo = repo_argument(arguments)
          limit = whole_number_argument(arguments, "limit", PIPELINE_LIMIT, MAX_PIPELINES)
          status = arguments["status"].presence
          fail! "status must be one of #{PIPELINE_STATUSES.join(', ')}" if status && PIPELINE_STATUSES.exclude?(status)

          found = pipelines_of(api(environment_row), repo, "target.branch" => branch_argument(arguments), "status" => status, "pagelen" => limit)
          return "No pipelines in #{repo} match." if found.empty?

          found.map { |each| pipeline_line(repo, each) }.join("\n")
        end

        def pipeline_steps(environment_row:, arguments:)
          repo = repo_argument(arguments)
          bitbucket = api(environment_row)
          pipeline = bitbucket.get("#{BitbucketApi.repository(repo)}/pipelines/#{uuid_argument(arguments, 'pipeline')}")
          steps = steps_of(bitbucket, repo, pipeline)
          heading = "Pipeline #{pipeline['build_number']} in #{repo}, #{outcome(pipeline)}, on #{pipeline.dig('target', 'ref_name')} " \
                    "at #{pipeline.dig('target', 'commit', 'hash').to_s[0, 12]}."
          Telemetry.result("#{heading}\n#{steps.map { |step| step_line(step) }.join("\n").presence || 'No steps listed.'}", link: pipeline_link(repo, pipeline))
        end

        def job_log(environment_row:, arguments:)
          repo = repo_argument(arguments)
          bitbucket = api(environment_row)
          pipeline, step = if arguments["step"].present?
            found = bitbucket.get("#{BitbucketApi.repository(repo)}/pipelines/#{uuid_argument(arguments, 'pipeline')}")
            [ found, bitbucket.get("#{BitbucketApi.repository(repo)}/pipelines/#{found['uuid']}/steps/#{uuid_argument(arguments, 'step')}") ]
          else
            newest_failed_step(bitbucket, repo, arguments)
          end
          return no_failed_step(repo, arguments) unless step

          raw = begin
            bitbucket.text("#{BitbucketApi.repository(repo)}/pipelines/#{pipeline['uuid']}/steps/#{step['uuid']}/log")
          rescue BitbucketApi::NotFound
            ""
          end
          heading = "Step #{step_name(step)} of pipeline #{pipeline['build_number']} in #{repo}, #{outcome(step)}, on #{pipeline.dig('target', 'ref_name')} " \
                    "at #{pipeline.dig('target', 'commit', 'hash').to_s[0, 12]}, finished #{step['completed_on'] || 'not yet'}."
          return Telemetry.result("#{heading}\nBitbucket keeps no log for this step, or no longer keeps it.", link: pipeline_link(repo, pipeline)) if raw.blank?

          kept, matched = build_log_lines(raw, arguments)
          Telemetry.result(log_text(heading, kept, matched), link: pipeline_link(repo, pipeline))
        end

        def ci_status(environment_row:, arguments:)
          repo = repo_argument(arguments)
          bitbucket = api(environment_row)
          branch = branch_argument(arguments) || bitbucket.get(BitbucketApi.repository(repo)).dig("mainbranch", "name")
          fail! "#{repo} has no main branch yet, so name a branch." if branch.blank?

          recent = pipelines_of(bitbucket, repo, "target.branch" => branch, "pagelen" => STREAK)
          latest = recent.first
          sections = [ latest_text(bitbucket, repo, branch, latest), streak_text(recent), environments_text(bitbucket, repo) ].compact
          Telemetry.result(sections.join("\n\n"), link: latest && pipeline_link(repo, latest))
        end

        private

        def pipelines_of(bitbucket, repo, query)
          Array(bitbucket.get("#{BitbucketApi.repository(repo)}/pipelines", { "sort" => NEWEST_FIRST }.merge(query))["values"])
        end

        def steps_of(bitbucket, repo, pipeline) = bitbucket.list("#{BitbucketApi.repository(repo)}/pipelines/#{pipeline['uuid']}/steps").first

        def branch_argument(arguments) = ref_argument(arguments, "branch")

        def uuid_argument(arguments, key)
          value = arguments[key].to_s.strip
          fail! "#{key} must be a uuid, as pipelines and pipeline_steps show it" unless value.match?(UUID_FORMAT)

          Http.segment(value.start_with?("{") ? value : "{#{value}}")
        end

        # A finished pipeline or step says how it ended, one still going says where it is.
        def outcome(item)
          state = item["state"] || {}
          (state.dig("result", "name") || state.dig("stage", "name") || state["name"]).to_s.downcase.presence || "unknown"
        end

        def failed?(item) = FAILED_RESULTS.include?(item.dig("state", "result", "name"))

        def step_name(step) = step["name"].presence || step["uuid"]

        # The commit a pipeline built, since Bitbucket gives a pipeline no page address (see commit_link).
        def pipeline_link(repo, pipeline) = pipeline.dig("target", "commit", "hash").present? ? commit_link(repo, pipeline.dig("target", "commit", "hash")) : nil

        def pipeline_line(repo, pipeline)
          "#{pipeline['created_on']}  pipeline #{pipeline['build_number']} #{pipeline['uuid']}  #{outcome(pipeline)}  #{pipeline.dig('target', 'ref_name')}  " \
            "#{pipeline.dig('target', 'commit', 'hash').to_s[0, 12]}  #{pipeline.dig('trigger', 'name').to_s.downcase} by " \
            "#{pipeline.dig('creator', 'display_name') || 'unknown'}"
        end

        def step_line(step)
          took = step["duration_in_seconds"] ? "  #{step['duration_in_seconds']}s" : ""
          "  #{step_name(step)}  #{outcome(step)}#{took}  step #{step['uuid']}"
        end

        # The newest failed pipeline that fits, and its first failed step.
        def newest_failed_step(bitbucket, repo, arguments)
          started, ended = Telemetry.range(arguments, default_minutes: CodeHost::LOG_RANGE_MINUTES, max_minutes: CodeHost::LOG_RANGE_MINUTES) if ranged?(arguments)
          failed = pipelines_of(bitbucket, repo, "target.branch" => branch_argument(arguments), "status" => FAILED, "pagelen" => PIPELINE_CANDIDATES)
          pipeline = failed.find do |candidate|
            at = Telemetry.parse_time(candidate["completed_on"] || candidate["created_on"])
            started.nil? || (at && at.between?(started, ended))
          end
          pipeline && [ pipeline, steps_of(bitbucket, repo, pipeline).find { |step| failed?(step) } ]
        end

        def ranged?(arguments) = %w[minutes start end].any? { |key| arguments[key].present? }

        def no_failed_step(repo, arguments)
          where = [ ("on #{arguments['branch']}" if arguments["branch"].present?), ("in that time" if ranged?(arguments)) ].compact.join(" ")
          "No failed pipeline step in #{repo}#{" #{where}" if where.present?} among its newest #{PIPELINE_CANDIDATES} failed pipelines."
        end

        def latest_text(bitbucket, repo, branch, latest)
          return "No pipeline has run on #{branch} in #{repo}. If its CI runs elsewhere, ask that connection." unless latest

          text = "Latest pipeline on #{branch}: #{latest['build_number']} (#{latest['uuid']}), #{outcome(latest)}, commit " \
                 "#{latest.dig('target', 'commit', 'hash').to_s[0, 12]}, started #{latest['created_on']}."
          return text unless failed?(latest)

          failed = steps_of(bitbucket, repo, latest).select { |step| failed?(step) }
          "#{text}\nFailed steps:\n#{failed.map { |step| step_line(step) }.join("\n").presence || '  none listed'}\njob_log with a pipeline and step reads why."
        end

        # When the branch last passed, so a failure that started a while ago reads differently from a new one.
        def streak_text(recent)
          return nil if recent.size < 2

          passed = recent.find { |pipeline| pipeline.dig("state", "result", "name") == SUCCESSFUL }
          since = if failed?(recent.first)
            passed ? " It last passed in pipeline #{passed['build_number']} at #{passed['created_on']}." : " None of these passed."
          end
          "The last #{recent.size} pipelines, newest first: #{recent.map { |pipeline| outcome(pipeline) }.join(', ')}.#{since}"
        end

        def environments_text(bitbucket, repo)
          deployments = deployments_of(bitbucket, repo)
          return nil if deployments.empty?

          latest = deployments.uniq { |deployment| deployment["environment_name"] }
          shown = latest.sort_by { |deployment| deployment["environment_name"].match?(CodeHost::PRODUCTION) ? 0 : 1 }.first(ENVIRONMENTS_SHOWN)
          lines = shown.map { |deployment| "  #{deployment['environment_name'].presence || 'unknown environment'}: #{deployment_line(deployment)}" }
          more = latest.size > ENVIRONMENTS_SHOWN ? "\n  #{latest.size - ENVIRONMENTS_SHOWN} more environments, recent_deployments reads them." : ""
          "Environments, what each last deployed:\n#{lines.join("\n")}#{more}"
        rescue BitbucketApi::Refused
          nil
        end
      end
    end
  end
end
