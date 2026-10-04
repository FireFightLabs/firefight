module Integrations
  module Packs
    class Gitlab
      # A project's CI as GitLab keeps it (doc/api/pipelines.md, jobs.md and environments.md): its pipelines, their jobs,
      # a job's log, and how the default branch and the environments stand now.
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

        def self.included(pack)
          repo = pack::REPO_PARAM
          pack.tool :pipelines,
                    description: "A project's pipelines, newest first, with their status, branch or tag, commit, what started them and their page",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo,
                      "ref" => { "type" => "string", "description" => "Only pipelines for this branch or tag (optional)" },
                      "status" => { "type" => "string", "enum" => PIPELINE_STATUSES, "description" => "Only pipelines in this status, such as failed (optional)" },
                      "since" => { "type" => "string", "description" => "Only pipelines updated at or after this time, as ISO 8601 (optional)" },
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{PIPELINE_LIMIT}, at most #{MAX_PIPELINES})" }
                    }, %w[repo]),
                    read_only: true

          pack.tool :pipeline_jobs,
                    description: "The jobs of one pipeline, by stage, with each one's status, why it failed and how long it took. Use job_log for a job's output",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo,
                      "pipeline_id" => { "type" => "integer", "description" => "The pipeline's id, as pipelines or ci_status shows it" },
                      "failed_only" => { "type" => "boolean", "description" => "Only the jobs that failed (optional)" }
                    }, %w[repo pipeline_id]),
                    read_only: true

          pack.tool :job_log,
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
                    description: "How a project's CI stands now: the latest pipeline on a branch (the default branch unless named) with " \
                                 "its failed jobs, how the last pipelines went and since when it fails, and what each environment last deployed",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo, "ref" => { "type" => "string", "description" => "The branch or tag (optional, the default branch)" }
                    }, %w[repo]),
                    read_only: true
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
          kept, matched = build_log_lines(raw, arguments)
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

        private

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
