module Integrations
  module Packs
    class Github
      # A repository's GitHub Actions, through the REST API's workflow runs, jobs and job logs (the actions paths of
      # github/rest-api-description), and what each deployment environment last received. A job that names an
      # environment writes a GitHub deployment, so deploys from Actions are read as deployments. The App needs Actions read.
      module Actions
        RUN_LIMIT = 10
        MAX_RUNS = 50
        RUN_CANDIDATES = 30
        FAILED_RUNS_READ = 3
        ENVIRONMENTS_SHOWN = 5
        FAILURE = "failure".freeze
        SUCCESS = "success".freeze
        # The status filter GitHub takes for runs, a status or a conclusion.
        RUN_STATUSES = %w[completed action_required cancelled failure neutral skipped stale success timed_out in_progress queued requested waiting pending].freeze
        FAILED_CONCLUSIONS = %w[failure timed_out].freeze

        def self.included(pack)
          pack.tool :workflow_runs,
                    description: "A repository's GitHub Actions workflow runs, newest first, with the workflow, its outcome, the branch and " \
                                 "commit, what started it and its page",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO,
                      "branch" => { "type" => "string", "description" => "Only runs for this branch (optional)" },
                      "status" => { "type" => "string", "enum" => RUN_STATUSES, "description" => "Only runs in this status or with this outcome, such as failure (optional)" },
                      "event" => { "type" => "string", "description" => "Only runs started by this event, such as push or pull_request (optional)" },
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{RUN_LIMIT}, at most #{MAX_RUNS})" }
                    }, %w[repo]),
                    read_only: true

          pack.tool :workflow_jobs,
                    description: "The jobs of one workflow run, with each one's outcome, the steps that failed and how long it took. Use job_log for a job's output",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO,
                      "run_id" => { "type" => "integer", "description" => "The run's id, as workflow_runs or ci_status shows it" },
                      "failed_only" => { "type" => "boolean", "description" => "Only the jobs that failed (optional)" }
                    }, %w[repo run_id]),
                    read_only: true

          pack.tool :job_log,
                    description: "The end of a GitHub Actions job's log, where it says why it failed, filtered by text if asked. Without a " \
                                 "job, the newest failed job in the repository, on a branch when one is named, in the time asked when one is given",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO,
                      "job_id" => { "type" => "integer", "description" => "The job's id, as workflow_jobs shows it (optional)" },
                      "branch" => { "type" => "string", "description" => "Only a job on this branch, when no job is named (optional)" },
                      **CodeHost::LOG_FILTER, **CodeHost::LOG_RANGE
                    }, %w[repo]),
                    read_only: true

          pack.tool :ci_status,
                    description: "How a repository's CI stands now: the latest run of each GitHub Actions workflow on a branch (the default " \
                                 "branch unless named), failing ones first with the jobs and steps that failed, and what each deployment " \
                                 "environment last received",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO, "branch" => { "type" => "string", "description" => "The branch (optional, the default branch)" }
                    }, %w[repo]),
                    read_only: true
        end

        def workflow_runs(environment_row:, arguments:)
          repo = repo_argument(arguments)
          status = arguments["status"].presence
          fail! "status must be one of #{RUN_STATUSES.join(', ')}" if status && RUN_STATUSES.exclude?(status)

          limit = whole_number_argument(arguments, "limit", RUN_LIMIT, MAX_RUNS)
          runs = runs_of(repo, GithubApp.installation_token(environment_row), "branch" => arguments["branch"].presence, "status" => status,
                                                                                "event" => arguments["event"].presence, "per_page" => limit)
          return "No workflow runs in #{repo} match." if runs.empty?

          runs.map { |run| run_line(run) }.join("\n")
        end

        def workflow_jobs(environment_row:, arguments:)
          repo = repo_argument(arguments)
          id = Integer(arguments["run_id"].to_s, exception: false)
          fail! "run_id must be a whole number" unless id&.positive?

          token = GithubApp.installation_token(environment_row)
          run = GithubApp.get("/repos/#{repo}/actions/runs/#{id}", token: token)
          jobs = jobs_of(repo, id, token)
          jobs = jobs.select { |job| FAILED_CONCLUSIONS.include?(job["conclusion"]) } if ActiveModel::Type::Boolean.new.cast(arguments["failed_only"])
          heading = "#{run['name']} run #{run['run_number']} (#{id}) in #{repo}, #{outcome(run)}, on #{run['head_branch']} at #{run['head_sha'].to_s[0, 12]}."
          lines = jobs.map { |job| job_line(job) }
          Telemetry.result("#{heading}\n#{lines.join("\n").presence || 'No jobs match.'}", link: actions_link(run["html_url"]))
        end

        def job_log(environment_row:, arguments:)
          repo = repo_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          job = if arguments["job_id"].present?
            id = Integer(arguments["job_id"].to_s, exception: false)
            fail! "job_id must be a whole number" unless id&.positive?

            GithubApp.get("/repos/#{repo}/actions/jobs/#{id}", token: token)
          else
            newest_failed_job(repo, token, arguments)
          end
          return no_failed_job(repo, arguments) unless job

          kept, matched = build_log_lines(GithubApp.download("/repos/#{repo}/actions/jobs/#{job['id']}/logs", token: token), arguments)
          failed = Array(job["steps"]).select { |step| FAILED_CONCLUSIONS.include?(step["conclusion"]) }.map { |step| step["name"] }
          heading = "Job #{job['id']} #{job['workflow_name']} / #{job['name']} in #{repo}, #{outcome(job)}, on #{job['head_branch']} " \
                    "at #{job['head_sha'].to_s[0, 12]}, finished #{job['completed_at'] || 'not yet'}." \
                    "#{" Failed #{'step'.pluralize(failed.size)}: #{failed.join(', ')}." if failed.any?}"
          Telemetry.result(log_text(heading, kept, matched), link: actions_link(job["html_url"]))
        end

        def ci_status(environment_row:, arguments:)
          repo = repo_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          branch = arguments["branch"].presence || GithubApp.get("/repos/#{repo}", token: token)["default_branch"]
          runs = runs_of(repo, token, "branch" => branch, "per_page" => RUN_CANDIDATES)
          latest = runs.uniq { |run| run["workflow_id"] }
          failing = latest.select { |run| FAILED_CONCLUSIONS.include?(run["conclusion"]) }
          sections = [ workflows_text(repo, branch, latest, failing, token), environments_text(repo, token) ].compact
          Telemetry.result(sections.join("\n\n"), link: actions_link((failing.first || latest.first)&.dig("html_url")))
        end

        private

        def runs_of(repo, token, query)
          Array(GithubApp.get("/repos/#{repo}/actions/runs?#{query.compact.to_query}", token: token)["workflow_runs"])
        end

        def jobs_of(repo, run_id, token)
          Array(GithubApp.get("/repos/#{repo}/actions/runs/#{run_id}/jobs?#{{ 'filter' => 'latest', 'per_page' => 100 }.to_query}", token: token)["jobs"])
        end

        def outcome(item) = item["conclusion"].presence || item["status"]

        def run_line(run)
          "#{run['created_at']}  run #{run['id']}  #{run['name']} ##{run['run_number']}  #{outcome(run)}  #{run['head_branch']}  " \
            "#{run['head_sha'].to_s[0, 12]}  #{run['event']} by #{run.dig('actor', 'login') || 'unknown'}  #{run['html_url']}"
        end

        def job_line(job)
          failed = Array(job["steps"]).select { |step| FAILED_CONCLUSIONS.include?(step["conclusion"]) }.map { |step| step["name"] }
          took = job["started_at"] && job["completed_at"] ? "  #{(Time.zone.parse(job['completed_at']) - Time.zone.parse(job['started_at'])).round}s" : ""
          "  #{job['name']}  #{outcome(job)}#{" at #{failed.join(', ')}" if failed.any?}#{took}  job #{job['id']}  #{job['html_url']}"
        end

        def actions_link(url) = url.present? ? Telemetry::Link.new(provider: "GitHub", url: url) : nil

        # The newest failed run that fits, and its first failed job.
        def newest_failed_job(repo, token, arguments)
          started, ended = Telemetry.range(arguments, default_minutes: CodeHost::LOG_RANGE_MINUTES, max_minutes: CodeHost::LOG_RANGE_MINUTES) if ranged?(arguments)
          runs = runs_of(repo, token, "branch" => arguments["branch"].presence, "status" => FAILURE, "per_page" => RUN_CANDIDATES)
          run = runs.find do |candidate|
            at = Telemetry.parse_time(candidate["updated_at"])
            started.nil? || (at && at.between?(started, ended))
          end
          run && jobs_of(repo, run["id"], token).find { |job| FAILED_CONCLUSIONS.include?(job["conclusion"]) }
        end

        def ranged?(arguments) = %w[minutes start end].any? { |key| arguments[key].present? }

        def no_failed_job(repo, arguments)
          where = [ ("on #{arguments['branch']}" if arguments["branch"].present?), ("in that time" if ranged?(arguments)) ].compact.join(" ")
          "No failed GitHub Actions run in #{repo}#{" #{where}" if where.present?} among its newest #{RUN_CANDIDATES} failed runs."
        end

        def workflows_text(repo, branch, latest, failing, token)
          return "No GitHub Actions workflow has run on #{branch} in #{repo}. If its CI runs elsewhere, ask that connection." if latest.empty?

          ordered = failing + (latest - failing)
          lines = ordered.map { |run| "  #{run['name']}: #{outcome(run)}, run #{run['id']} at #{run['created_at']}, commit #{run['head_sha'].to_s[0, 12]}  #{run['html_url']}" }
          details = failing.first(FAILED_RUNS_READ).map do |run|
            failed = jobs_of(repo, run["id"], token).select { |job| FAILED_CONCLUSIONS.include?(job["conclusion"]) }
            "#{run['name']} failed in:\n#{failed.map { |job| job_line(job) }.join("\n").presence || '  no failed job listed'}"
          end
          summary = failing.any? ? "#{failing.size} of #{latest.size} workflows fail on #{branch}." : "Every workflow's latest run on #{branch} passed or is running."
          [ "#{summary} The latest run of each:\n#{lines.join("\n")}", *details, ("job_log with a job_id reads why." if failing.any?) ].compact.join("\n\n")
        end

        # What each environment last received, from the deployments a job naming an environment writes.
        def environments_text(repo, token)
          deployments = Array(GithubApp.get("/repos/#{repo}/deployments?#{{ 'per_page' => RUN_CANDIDATES }.to_query}", token: token))
          return nil if deployments.empty?

          latest = deployments.uniq { |deployment| deployment["environment"] }.first(ENVIRONMENTS_SHOWN)
          lines = latest.map do |deployment|
            "  #{deployment['environment']}: #{deployment['sha'].to_s[0, 12]} (#{deployment['ref']}) at #{deployment['created_at']}, " \
              "#{deployment_state(repo, deployment['id'], token)}, by #{deployment.dig('creator', 'login') || 'unknown'}"
          end
          "Environments, what each last received:\n#{lines.join("\n")}"
        end
      end
    end
  end
end
