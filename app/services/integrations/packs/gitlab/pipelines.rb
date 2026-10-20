module Integrations
  module Packs
    class Gitlab
      # A project's CI as GitLab keeps it (doc/api/pipelines.md, jobs.md and environments.md): its pipelines, their jobs,
      # a job's log, and how the default branch and the environments stand now. Retrying a pipeline's failed and canceled
      # jobs, running a new pipeline and canceling one are changes (doc/api/pipelines.md, retry, create and cancel), as are
      # retrying, running a manual job and canceling one job (doc/api/jobs.md, retry, play and cancel), so they go through
      # the gateway as writes and a member needs a grant for them. They need a token with the api scope.
      module Pipelines
        PIPELINE_LIMIT = 10
        MAX_PIPELINES = 50
        JOB_CANDIDATES = 50
        STREAK = 10
        ENVIRONMENTS_SHOWN = 5
        FAILED = "failed".freeze
        SUCCESS = "success".freeze
        AVAILABLE = "available".freeze
        PIPELINE_STATUSES = %w[created waiting_for_resource preparing pending running success failed canceling canceled skipped manual scheduled].freeze
        # A pipeline in one of these has ended, so there is nothing left to cancel. GitLab answers 200 to a cancel whatever
        # the pipeline's state (doc/api/pipelines.md, cancel), so this is checked first.
        FINISHED_STATUSES = %w[success failed canceled skipped].freeze
        # GitLab marks a log's collapsible sections with lines such as section_start:1700000000:build_script, which say nothing.
        SECTION_MARK = /\A\s*section_(start|end):\d+:[\w.\-]+(\[[^\]]*\])?/
        # What every change here needs (doc/ci/pipelines, pipeline security on protected branches).
        WRITE_NEEDS = "Running, retrying or canceling a pipeline needs a token with the api scope, from someone who may run " \
                      "pipelines in the project, and on a protected branch someone allowed to merge or push to it".freeze
        FOLLOW = "pipeline_jobs with its pipeline_id, or ci_status, follows it".freeze
        # GitLab's list of pipelines gives no start or finish (doc/api/pipelines.md, list project pipelines), so each one is
        # read again on its own, which gives started_at and finished_at. That keeps the history short.
        HISTORY_LIMIT = 10
        MAX_HISTORY = 20
        HISTORY_CANDIDATES = 50
        # A pipeline's jobs are read this many pages of 100 at most, and so are each child pipeline's.
        JOB_PAGES = 5
        MANUAL = "manual".freeze
        # Statuses a job can be retried from (doc/api/jobs.md, job status values), since one still going has nothing to retry.
        JOB_ENDED = %w[success failed canceled skipped].freeze
        # A pipeline's or job's status in Firefight's words (the status values of doc/api/pipelines.md and jobs.md). A
        # manual job waits for someone to start it, so it waits on a person rather than a runner.
        HISTORY_STATUSES = {
          "created" => Capabilities::History::QUEUED, "waiting_for_resource" => Capabilities::History::QUEUED,
          "preparing" => Capabilities::History::QUEUED, "pending" => Capabilities::History::QUEUED, "scheduled" => Capabilities::History::QUEUED,
          MANUAL => Capabilities::History::WAITING, "running" => Capabilities::History::RUNNING, "canceling" => Capabilities::History::RUNNING,
          "success" => Capabilities::History::SUCCEEDED, "failed" => Capabilities::History::FAILED,
          "canceled" => Capabilities::History::CANCELLED, "skipped" => Capabilities::History::CANCELLED
        }.freeze

        def self.included(pack)
          repo = pack::REPO_PARAM
          pack.tool :pipelines,
                    summary: "Lists a project's pipelines with their status, branch and commit.",
                    description: "A project's pipelines, newest first, with their status, branch or tag, commit, what started them and their page",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo,
                      "ref" => { "type" => "string", "description" => "Only pipelines for this branch or tag (optional)" },
                      "status" => { "type" => "string", "enum" => PIPELINE_STATUSES, "description" => "Only pipelines in this status, such as failed (optional)" },
                      "since" => { "type" => "string", "description" => "Only pipelines updated at or after this time, as ISO 8601 (optional)" },
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{PIPELINE_LIMIT}, at most #{MAX_PIPELINES})" }
                    }, %w[repo]),
                    read_only: true

          pack.tool :ci_runs,
                    summary: "Lists recent pipelines with how long each took compared with the usual time.",
                    description: "A project's pipelines, newest first, each with its status, when it started and finished and how long " \
                                 "it took, and how long finished pipelines usually take. A pipeline waiting on a manual job says so. A " \
                                 "name no pipeline has, such as production, reads the project's deployments as runs",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo,
                      "name" => { "type" => "string", "description" => "Only pipelines with this name, or whose name contains it, such as release, or else deployments to an environment it names (optional)" },
                      "ref" => { "type" => "string", "description" => "Only pipelines for this branch or tag (optional)" },
                      "status" => { "type" => "string", "enum" => PIPELINE_STATUSES, "description" => "Only pipelines in this status, such as failed or manual (optional)" },
                      "source" => { "type" => "string", "description" => "Only pipelines started this way, such as push, schedule, web or merge_request_event (optional)" },
                      "run" => { "type" => "string", "description" => "Only this pipeline, by its id, with each job and its child pipelines' jobs, or a deployment by the id this answer gives it (optional)" },
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{HISTORY_LIMIT}, at most #{MAX_HISTORY})" }
                    }, %w[repo]),
                    read_only: true

          pack.tool :pipeline_jobs,
                    summary: "Shows the jobs of a pipeline by stage, with why any failed.",
                    description: "The jobs of one pipeline, by stage, with each one's status, why it failed and how long it took. Use job_log for a job's output",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo,
                      "pipeline_id" => { "type" => "integer", "description" => "The pipeline's id, as pipelines or ci_status shows it" },
                      "failed_only" => { "type" => "boolean", "description" => "Only the jobs that failed (optional)" }
                    }, %w[repo pipeline_id]),
                    read_only: true

          pack.tool :job_log,
                    summary: "Shows the end of a CI job's log, where it says why the job failed.",
                    description: "The end of a job's log, where it says why it failed, filtered by text if asked. Without a job, the newest " \
                                 "failed job in the project, on a branch when one is named, in the time asked when one is given",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo,
                      "job_id" => { "type" => "integer", "description" => "The job's id, as pipeline_jobs shows it (optional)" },
                      "ref" => { "type" => "string", "description" => "Only a job on this branch or tag, when no job is named (optional)" },
                      **CodeHost::LOG_FILTER, **CodeHost::LOG_RANGE
                    }, %w[repo]),
                    read_only: true

          pack.tool :ci_status,
                    summary: "Shows how CI stands on a branch, its failed jobs and recent deploys.",
                    description: "How a project's CI stands now: the latest pipeline on a branch (the default branch unless named) with " \
                                 "its failed jobs, how the last pipelines went and since when it fails, and what each environment last deployed",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo, "ref" => { "type" => "string", "description" => "The branch or tag (optional, the default branch)" }
                    }, %w[repo]),
                    read_only: true

          pipeline_id = { "type" => "integer", "description" => "The pipeline's id, as pipelines or ci_status shows it" }
          pack.tool :retry_pipeline,
                    summary: "Retries a pipeline's failed and canceled jobs.",
                    description: "Retry a pipeline's failed and canceled jobs, the retry GitLab offers, on the same commit. For a failure " \
                                 "that is not the code, such as a flaky test or a runner that went away",
                    params_schema: CodeHost::Code.object_schema({ "repo" => repo, "pipeline_id" => pipeline_id }, %w[repo pipeline_id]),
                    read_only: false

          pack.tool :run_pipeline,
                    summary: "Runs a new pipeline on a branch or tag.",
                    description: "Run a new pipeline on a branch or tag, with CI/CD variables or inputs if asked",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo,
                      "ref" => { "type" => "string", "description" => "The branch or tag (optional, the default branch)" },
                      "variables" => { "type" => "object", "additionalProperties" => { "type" => "string" },
                                       "description" => "CI/CD variables by name, never a secret, since they are shown and kept (optional)" },
                      "inputs" => { "type" => "object", "description" => "The pipeline's inputs by name, as its spec declares them (optional, their defaults)" }
                    }, %w[repo]),
                    read_only: false

          pack.tool :cancel_pipeline,
                    summary: "Cancels a pipeline's unfinished jobs.",
                    description: "Cancel a pipeline's jobs that have not finished, such as a deploy that should not go out",
                    params_schema: CodeHost::Code.object_schema({ "repo" => repo, "pipeline_id" => pipeline_id }, %w[repo pipeline_id]),
                    read_only: false

          job_id = { "type" => "integer", "description" => "The job's id, as pipeline_jobs shows it" }
          pack.tool :retry_job,
                    summary: "Runs one finished job again as a new job.",
                    description: "Run one finished job again as a new job in its pipeline, on the same commit. For one flaky job, or to " \
                                 "deploy again from a deploy job",
                    params_schema: CodeHost::Code.object_schema({ "repo" => repo, "job_id" => job_id }, %w[repo job_id]),
                    read_only: false

          pack.tool :play_job,
                    summary: "Starts a manual job that is waiting for someone to run it.",
                    description: "Start a job that waits for someone to run it by hand, such as a manual deploy to production",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo, "job_id" => job_id,
                      "variables" => { "type" => "object", "additionalProperties" => { "type" => "string" },
                                       "description" => "CI/CD variables for this run of the job, never a secret, since they are shown and kept (optional)" }
                    }, %w[repo job_id]),
                    read_only: false

          pack.tool :cancel_job,
                    summary: "Cancels one job that has not finished.",
                    description: "Cancel one job that is pending or running, leaving the rest of its pipeline as it is",
                    params_schema: CodeHost::Code.object_schema({ "repo" => repo, "job_id" => job_id }, %w[repo job_id]),
                    read_only: false
        end

        def pipelines(environment_row:, arguments:)
          repo = repo_argument(arguments)
          limit = whole_number_argument(arguments, "limit", PIPELINE_LIMIT, MAX_PIPELINES)
          status = arguments["status"].presence
          fail! "status must be one of #{PIPELINE_STATUSES.join(', ')}" if status && PIPELINE_STATUSES.exclude?(status)

          query = { "ref" => ref_argument(arguments), "status" => status, "updated_after" => since_argument(arguments)&.iso8601, "per_page" => limit }
          found = Array(api(environment_row).get("#{GitlabApi.project(repo)}/pipelines", query))
          return "No pipelines in #{repo} match." if found.empty?

          found.map { |pipeline| pipeline_line(pipeline) }.join("\n")
        end

        # status, source, ref and a name go to GitLab's own filters. GitLab matches a name whole, so a name it finds no
        # pipeline by is looked for inside the newest pipelines' names, and then among the deployments' environments.
        def ci_runs(environment_row:, arguments:)
          repo = repo_argument(arguments)
          gitlab = api(environment_row)
          asked = arguments["run"].to_s.strip
          return one_deployment(gitlab, repo, asked.delete_prefix(DEPLOYMENT_RUN)) if asked.start_with?(DEPLOYMENT_RUN)
          return one_pipeline(gitlab, repo, positive_id(arguments, "run")) if asked.present?

          limit = whole_number_argument(arguments, "limit", HISTORY_LIMIT, MAX_HISTORY)
          status = arguments["status"].presence
          fail! "status must be one of #{PIPELINE_STATUSES.join(', ')}" if status && PIPELINE_STATUSES.exclude?(status)

          name = arguments["name"].to_s.strip.presence
          query = { "ref" => ref_argument(arguments), "status" => status, "source" => arguments["source"].presence, "per_page" => limit }.compact
          chosen = name ? named_pipelines(gitlab, repo, query, name) : Array(gitlab.get("#{GitlabApi.project(repo)}/pipelines", query))
          if name && chosen.empty?
            return Capabilities::History.result(deployment_runs(gitlab, repo, limit, name), what: "deployments in #{repo}, since no pipeline is named #{name}",
                                                link: link(gitlab.web_url(repo, "-", "environments")), name: name, limit: limit)
          end

          runs = chosen.first(limit).map { |pipeline| history_run(gitlab.get("#{GitlabApi.project(repo)}/pipelines/#{pipeline['id']}")) }
          Capabilities::History.result(runs, what: "pipelines in #{repo}", link: link(gitlab.web_url(repo, "-", "pipelines")), name: name, limit: limit)
        end

        def retry_job(environment_row:, arguments:)
          repo = repo_argument(arguments)
          gitlab = api(environment_row)
          job = gitlab.get("#{GitlabApi.project(repo)}/jobs/#{positive_id(arguments, 'job_id')}")
          fail! "#{job_name(job, repo)} is still #{job['status']}, so it cannot run again until it finishes. cancel_job stops it." unless JOB_ENDED.include?(job["status"])

          retried = changing("retry #{job_name(job, repo)}") { gitlab.post("#{GitlabApi.project(repo)}/jobs/#{job['id']}/retry") }
          Telemetry.result("#{job_name(job, repo)} runs again as job #{retried['id']}, on #{job['ref']} at #{job_commit(job)}. It is " \
                           "#{retried['status'] || 'starting'}. #{FOLLOW}.", link: link(retried["web_url"] || job["web_url"]))
        end

        def play_job(environment_row:, arguments:)
          repo = repo_argument(arguments)
          gitlab = api(environment_row)
          job = gitlab.get("#{GitlabApi.project(repo)}/jobs/#{positive_id(arguments, 'job_id')}")
          fail! "#{job_name(job, repo)} is #{job['status']}, not a manual job waiting to be started. retry_job runs a finished one again." unless job["status"] == MANUAL

          variables = hash_argument(arguments, "variables").map { |key, value| { "key" => key.to_s, "value" => value.to_s } }
          started = changing("start #{job_name(job, repo)}") do
            gitlab.post("#{GitlabApi.project(repo)}/jobs/#{job['id']}/play", { "job_variables_attributes" => variables.presence }.compact)
          end
          given = variables.any? ? " with #{variables.map { |variable| variable['key'] }.to_sentence}" : ""
          Telemetry.result("Started #{job_name(job, repo)}#{given}, on #{job['ref']} at #{job_commit(job)}. It is #{started['status'] || 'starting'}. #{FOLLOW}.",
                           link: link(started["web_url"] || job["web_url"]))
        end

        def cancel_job(environment_row:, arguments:)
          repo = repo_argument(arguments)
          gitlab = api(environment_row)
          job = gitlab.get("#{GitlabApi.project(repo)}/jobs/#{positive_id(arguments, 'job_id')}")
          fail! "#{job_name(job, repo)} already finished, #{job['status']}, so there is nothing to cancel." if JOB_ENDED.include?(job["status"])

          canceled = changing("cancel #{job_name(job, repo)}") { gitlab.post("#{GitlabApi.project(repo)}/jobs/#{job['id']}/cancel") }
          Telemetry.result("Canceling #{job_name(job, repo)}, on #{job['ref']} at #{job_commit(job)}. It is #{canceled['status'] || 'canceling'}, and " \
                           "the rest of its pipeline goes on as it was. #{FOLLOW}.", link: link(canceled["web_url"] || job["web_url"]))
        end

        def pipeline_jobs(environment_row:, arguments:)
          repo = repo_argument(arguments)
          id = positive_id(arguments, "pipeline_id")
          gitlab = api(environment_row)
          query = ActiveModel::Type::Boolean.new.cast(arguments["failed_only"]) ? { "scope" => [ FAILED ] } : {}
          jobs, more = gitlab.list("#{GitlabApi.project(repo)}/pipelines/#{id}/jobs", query)
          link = link(gitlab.web_url(repo, "-", "pipelines", id))
          return Telemetry.result("Pipeline #{id} in #{repo} has no#{' failed' if query.any?} jobs.", link: link) if jobs.empty?

          lines = jobs.sort_by { |job| job["id"].to_i }.map { |job| job_line(job) }
          lines << "More jobs than these." if more
          Telemetry.result("Pipeline #{id} in #{repo}, #{jobs.size} jobs:\n#{lines.join("\n")}", link: link)
        end

        def job_log(environment_row:, arguments:)
          repo = repo_argument(arguments)
          gitlab = api(environment_row)
          job = if arguments["job_id"].present?
            gitlab.get("#{GitlabApi.project(repo)}/jobs/#{positive_id(arguments, 'job_id')}")
          else
            newest_failed_job(gitlab, repo, arguments)
          end
          return no_failed_job(repo, arguments) unless job

          raw = begin
            gitlab.text("#{GitlabApi.project(repo)}/jobs/#{job['id']}/trace")
          rescue GitlabApi::NotFound
            ""
          end
          kept, matched = build_log_lines(raw, arguments, marks: SECTION_MARK)
          reason = job["failure_reason"].present? ? ", #{job['failure_reason'].tr('_', ' ')}" : ""
          heading = "Job #{job['id']} #{job['stage']}/#{job['name']} in #{repo}, #{job['status']}#{reason}, on #{job['ref']} " \
                    "at #{job.dig('commit', 'short_id') || job.dig('pipeline', 'sha').to_s[0, 8]}, finished #{job['finished_at'] || 'not yet'}."
          return Telemetry.result("#{heading}\nGitLab keeps no log for this job.", link: link(job["web_url"])) if raw.blank?

          Telemetry.result(log_text(heading, kept, matched), link: link(job["web_url"]))
        end

        def ci_status(environment_row:, arguments:)
          repo = repo_argument(arguments)
          gitlab = api(environment_row)
          ref = ref_argument(arguments) || gitlab.get(GitlabApi.project(repo))["default_branch"]
          fail! "#{repo} has no default branch yet, so name a branch with ref." if ref.blank?

          recent = Array(gitlab.get("#{GitlabApi.project(repo)}/pipelines", "ref" => ref, "per_page" => STREAK))
          latest = recent.first
          sections = [ latest_text(gitlab, repo, ref, latest), streak_text(recent), environments_text(gitlab, repo) ].compact
          Telemetry.result(sections.join("\n\n"), link: latest && link(latest["web_url"]))
        end

        def retry_pipeline(environment_row:, arguments:)
          repo = repo_argument(arguments)
          id = positive_id(arguments, "pipeline_id")
          gitlab = api(environment_row)
          pipeline = gitlab.get("#{GitlabApi.project(repo)}/pipelines/#{id}")
          fail! "Pipeline #{id} in #{repo} passed, so it has no failed or canceled jobs to retry. run_pipeline runs a new one." if pipeline["status"] == SUCCESS

          retried = changing("retry pipeline #{id} in #{repo}") { gitlab.post("#{GitlabApi.project(repo)}/pipelines/#{id}/retry") }
          Telemetry.result("Retrying the failed and canceled jobs of pipeline #{id} in #{repo}, on #{pipeline['ref']} at #{pipeline['sha'].to_s[0, 12]}. " \
                           "It is #{retried['status'] || 'starting'}. #{FOLLOW}.", link: link(retried["web_url"] || pipeline["web_url"]))
        end

        def run_pipeline(environment_row:, arguments:)
          repo = repo_argument(arguments)
          gitlab = api(environment_row)
          ref = ref_argument(arguments) || gitlab.get(GitlabApi.project(repo))["default_branch"]
          fail! "#{repo} has no default branch yet, so name a branch or tag with ref." if ref.blank?

          variables = hash_argument(arguments, "variables").map { |key, value| { "key" => key.to_s, "value" => value.to_s } }
          inputs = hash_argument(arguments, "inputs")
          body = { "ref" => ref, "variables" => variables.presence, "inputs" => inputs.presence }.compact
          started = changing("run a pipeline on #{ref} in #{repo}") { gitlab.post("#{GitlabApi.project(repo)}/pipeline", body) }
          given = variables.any? ? " with #{variables.map { |variable| variable['key'] }.to_sentence}" : ""
          Telemetry.result("Started pipeline #{started['id']} on #{ref} at #{started['sha'].to_s[0, 12]} in #{repo}#{given}. It is #{started['status']}. " \
                           "#{FOLLOW}.", link: link(started["web_url"]))
        end

        def cancel_pipeline(environment_row:, arguments:)
          repo = repo_argument(arguments)
          id = positive_id(arguments, "pipeline_id")
          gitlab = api(environment_row)
          pipeline = gitlab.get("#{GitlabApi.project(repo)}/pipelines/#{id}")
          fail! "Pipeline #{id} in #{repo} already finished, #{pipeline['status']}, so there is nothing to cancel." if FINISHED_STATUSES.include?(pipeline["status"])

          canceled = changing("cancel pipeline #{id} in #{repo}") { gitlab.post("#{GitlabApi.project(repo)}/pipelines/#{id}/cancel") }
          Telemetry.result("Canceling pipeline #{id} in #{repo}, on #{pipeline['ref']} at #{pipeline['sha'].to_s[0, 12]}. It is " \
                           "#{canceled['status'] || 'canceling'}. #{FOLLOW}.", link: link(canceled["web_url"] || pipeline["web_url"]))
        end

        # Whoever started the pipeline, matched to a member by the public address their GitLab profile shows. A job is
        # asked about by the pipeline it runs in.
        def owner_of(tool_name, environment_row:, arguments:)
          return super unless %w[cancel_pipeline cancel_job].include?(tool_name)
          if tool_name == "cancel_job"
            job = api(environment_row).get("#{GitlabApi.project(repo_argument(arguments))}/jobs/#{positive_id(arguments, 'job_id')}")
            arguments = arguments.merge("pipeline_id" => job.dig("pipeline", "id"))
          end

          repo = repo_argument(arguments)
          gitlab = api(environment_row)
          pipeline = gitlab.get("#{GitlabApi.project(repo)}/pipelines/#{positive_id(arguments, 'pipeline_id')}")
          user = pipeline["user"].to_h
          return if user["username"].blank?

          profile = user["id"] ? gitlab.get("/users/#{Integer(user['id'])}") : {}
          Owner.new(name: user["name"].presence || user["username"], email: profile.to_h["public_email"].presence, role: Owner::ROLE_STARTED,
                    what: "pipeline #{pipeline['id']} in #{repo}")
        end

        private

        # A change GitLab refused is said with what it needs, so a person knows which token or role to give.
        def changing(what)
          yield
        rescue GitlabApi::Refused => error
          fail! Sentence.join("GitLab refused to #{what}", error, after: WRITE_NEEDS)
        end

        def hash_argument(arguments, key)
          value = arguments[key]
          return {} if value.blank?
          fail! "#{key} must be an object of names and values" unless value.is_a?(Hash)

          value
        end

        # A pipeline without a name of its own is called by the branch or tag it ran on.
        def history_run(pipeline)
          Capabilities::History::Run.new(
            id: pipeline["id"].to_s, number: pipeline["iid"]&.to_s, name: pipeline["name"].presence || "pipeline on #{pipeline['ref']}",
            status: Capabilities::History.status(pipeline["status"], HISTORY_STATUSES),
            started_at: Telemetry.parse_time(pipeline["started_at"] || pipeline["created_at"]), finished_at: Telemetry.parse_time(pipeline["finished_at"]),
            url: pipeline["web_url"], detail: "#{pipeline['ref']} at #{pipeline['sha'].to_s[0, 12]}, #{pipeline['source']}"
          )
        end

        # One pipeline with every job, each with its log read by job_log, so a watch hears the first job that failed while the
        # pipeline still goes. A job allowed to fail is not a failure of the pipeline. A trigger job is a part of its own, and
        # the child pipeline it started in the same project has its jobs read too, named under it.
        def one_pipeline(gitlab, repo, id)
          pipeline = gitlab.get("#{GitlabApi.project(repo)}/pipelines/#{id}")
          parts, more = pipeline_parts(gitlab, repo, id)
          trigger_jobs(gitlab, repo, id).each do |trigger|
            parts << trigger_part(trigger)
            downstream = trigger["downstream_pipeline"]
            parts.concat(child_parts(gitlab, repo, downstream["id"], "#{trigger['name']} > ")) if downstream.is_a?(Hash) && downstream["id"]
          end
          cut = more ? ", of which only the first #{JOB_PAGES * GitlabApi::PAGE_SIZE} jobs were read" : ""
          Capabilities::History.result([ history_run(pipeline).with(parts: parts) ], what: "pipelines in #{repo}#{cut}", link: link(pipeline["web_url"]))
        end

        # The pipeline's jobs as parts, and whether it held more than were read.
        def pipeline_parts(gitlab, repo, id, prefix = "")
          jobs, more = gitlab.list("#{GitlabApi.project(repo)}/pipelines/#{id}/jobs", {}, pages: JOB_PAGES)
          [ Array(jobs).reject { |job| job["allow_failure"] }.map { |job| history_part(repo, job, prefix) }, more ]
        end

        # A downstream pipeline in another project is not found under this one, so only its trigger job stands for it.
        def child_parts(gitlab, repo, id, prefix)
          pipeline_parts(gitlab, repo, id, prefix).first
        rescue GitlabApi::NotFound
          []
        end

        # GitLab 19.2 renamed a pipeline's bridges to trigger_jobs and keeps the old route, so an older GitLab is read by it.
        def trigger_jobs(gitlab, repo, id)
          listed, = gitlab.list("#{GitlabApi.project(repo)}/pipelines/#{id}/trigger_jobs")
          Array(listed)
        rescue GitlabApi::NotFound
          Array(gitlab.list("#{GitlabApi.project(repo)}/pipelines/#{id}/bridges").first)
        end

        def trigger_part(trigger)
          downstream = trigger["downstream_pipeline"].to_h
          Capabilities::History::Part.new(
            id: trigger["id"].to_s, name: "#{trigger['stage']} / #{trigger['name']}", status: Capabilities::History.status(trigger["status"], HISTORY_STATUSES),
            started_at: Telemetry.parse_time(trigger["started_at"]), finished_at: Telemetry.parse_time(trigger["finished_at"]),
            url: downstream["web_url"].presence || trigger["web_url"], detail: ("starts pipeline #{downstream['id']}, #{downstream['status']}" if downstream["id"])
          )
        end

        def history_part(repo, job, prefix = "")
          status = Capabilities::History.status(job["status"], HISTORY_STATUSES)
          detail = if job["failure_reason"].present? then "with #{job['failure_reason'].tr('_', ' ')}"
          elsif job["status"] == MANUAL then "waiting for someone to start it, play_job starts job #{job['id']}"
          end
          Capabilities::History::Part.new(
            id: job["id"].to_s, name: "#{prefix}#{job['stage']} / #{job['name']}", status: status, started_at: Telemetry.parse_time(job["started_at"]),
            finished_at: Telemetry.parse_time(job["finished_at"]), url: job["web_url"], detail: detail,
            log: { Capabilities::History::LOG_TOOL => "job_log", Capabilities::History::LOG_ARGUMENTS => { "repo" => repo, "job_id" => job["id"] } }
          )
        end

        # GitLab's name filter matches a name whole, so a name it finds nothing by is looked for inside the newest names.
        def named_pipelines(gitlab, repo, query, name)
          exact = Array(gitlab.get("#{GitlabApi.project(repo)}/pipelines", query.merge("name" => name)))
          return exact if exact.any?

          Array(gitlab.get("#{GitlabApi.project(repo)}/pipelines", query.merge("per_page" => HISTORY_CANDIDATES))).select { |pipeline| history_run(pipeline).called?(name) }
        end

        def job_name(job, repo) = "Job #{job['id']} #{job['stage']}/#{job['name']} in #{repo}"

        def job_commit(job) = job.dig("commit", "short_id") || job.dig("pipeline", "sha").to_s[0, 8]

        def pipeline_line(pipeline)
          "#{pipeline['created_at']}  pipeline #{pipeline['id']}  #{pipeline['status']}  #{pipeline['ref']}  #{pipeline['sha'].to_s[0, 12]}  " \
            "#{pipeline['source']}  #{pipeline['web_url']}"
        end

        def job_line(job)
          failure = job["failure_reason"].present? ? " (#{job['failure_reason'].tr('_', ' ')})" : ""
          allowed = job["allow_failure"] && job["status"] == FAILED ? ", allowed to fail" : ""
          took = job["duration"] ? "  #{job['duration'].to_f.round}s" : ""
          "  #{job['stage']} / #{job['name']}  #{job['status']}#{failure}#{allowed}#{took}  job #{job['id']}  #{job['web_url']}"
        end

        def positive_id(arguments, key)
          id = Integer(arguments[key].to_s, exception: false)
          fail! "#{key} must be a whole number" unless id&.positive?

          id
        end

        # GitLab lists a project's jobs newest first, so the first failed one that fits is the newest.
        def newest_failed_job(gitlab, repo, arguments)
          ref = ref_argument(arguments)
          started, ended = Telemetry.range(arguments, default_minutes: CodeHost::LOG_RANGE_MINUTES, max_minutes: CodeHost::LOG_RANGE_MINUTES) if ranged?(arguments)
          Array(gitlab.get("#{GitlabApi.project(repo)}/jobs", "scope" => [ FAILED ], "per_page" => JOB_CANDIDATES)).find do |job|
            finished = Telemetry.parse_time(job["finished_at"])
            (ref.nil? || job["ref"] == ref) && (started.nil? || (finished && finished.between?(started, ended)))
          end
        end

        def ranged?(arguments) = %w[minutes start end].any? { |key| arguments[key].present? }

        def no_failed_job(repo, arguments)
          where = [ ("on #{arguments['ref']}" if arguments["ref"].present?), ("in that time" if ranged?(arguments)) ].compact.join(" ")
          "No failed job in #{repo}#{" #{where}" if where.present?} among its newest #{JOB_CANDIDATES} failed jobs."
        end

        def latest_text(gitlab, repo, ref, latest)
          return "No pipeline has run on #{ref} in #{repo}. If its CI runs elsewhere, ask that connection." unless latest

          text = "Latest pipeline on #{ref}: #{latest['id']}, #{latest['status']}, commit #{latest['sha'].to_s[0, 12]}, started by #{latest['source']} at #{latest['created_at']}."
          return text unless latest["status"] == FAILED

          failed = Array(gitlab.get("#{GitlabApi.project(repo)}/pipelines/#{latest['id']}/jobs", "scope" => [ FAILED ], "per_page" => GitlabApi::PAGE_SIZE))
          "#{text}\nFailed jobs:\n#{failed.map { |job| job_line(job) }.join("\n").presence || '  none listed'}\njob_log with a job_id reads why."
        end

        # When the branch last passed, so a failure that started a while ago reads differently from a new one.
        def streak_text(recent)
          return nil if recent.size < 2

          statuses = recent.map { |pipeline| pipeline["status"] }
          passed = recent.find { |pipeline| pipeline["status"] == SUCCESS }
          since = if recent.first["status"] == FAILED
            passed ? " It last passed in pipeline #{passed['id']} at #{passed['created_at']}." : " None of these passed."
          end
          "The last #{recent.size} pipelines, newest first: #{statuses.join(', ')}.#{since}"
        end

        def environments_text(gitlab, repo)
          environments = Array(gitlab.get("#{GitlabApi.project(repo)}/environments", "states" => AVAILABLE, "per_page" => GitlabApi::PAGE_SIZE))
          return nil if environments.empty?

          shown = environments.sort_by { |environment| environment["name"].to_s.match?(CodeHost::PRODUCTION) ? 0 : 1 }.first(ENVIRONMENTS_SHOWN)
          lines = shown.map do |environment|
            deployment = gitlab.get("#{GitlabApi.project(repo)}/environments/#{environment['id']}")["last_deployment"]
            last = deployment ? "#{deployment['status']} #{deployment['sha'].to_s[0, 12]} (#{deployment['ref']}) at #{deployment['created_at']} by #{deployment.dig('user', 'username') || 'unknown'}" : "nothing deployed yet"
            "  #{environment['name']}#{" #{environment['external_url']}" if environment['external_url'].present?}: #{last}"
          end
          more = environments.size > ENVIRONMENTS_SHOWN ? "\n  #{environments.size - ENVIRONMENTS_SHOWN} more environments, recent_deployments reads them." : ""
          "Environments, what each last deployed:\n#{lines.join("\n")}#{more}"
        rescue GitlabApi::Refused
          nil
        end
      end
    end
  end
end
