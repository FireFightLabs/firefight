module Integrations
  module Packs
    class Github
      # A repository's GitHub Actions, through the REST API's workflow runs, jobs and job logs (the actions paths of
      # github/rest-api-description), and what each deployment environment last received. A job that names an
      # environment writes a GitHub deployment, so deploys from Actions are read as deployments. The App needs Actions read.
      # Rerunning a run, starting a workflow by hand and canceling a run are changes (actions/runs/{run_id}/rerun,
      # rerun-failed-jobs and cancel, actions/workflows/{workflow_id}/dispatches), so they go through
      # the gateway as writes and need Actions read and write.
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
        COMPLETED = "completed".freeze
        ACTIVE = "active".freeze
        DISPATCH = "workflow_dispatch".freeze
        # The permission every change here needs, as GitHub names it in an App's repository permissions.
        WRITE_PERMISSION = "Actions: read and write".freeze
        # A workflow is named by its id or its file's name, such as ci.yml, which GitHub takes in place of the id.
        WORKFLOW_FILE = /\A[\w.\-]+\.ya?ml\z/
        # The types a workflow_dispatch input can declare (workflow syntax, on.workflow_dispatch.inputs.<input_id>.type).
        BOOLEAN_INPUT = "boolean".freeze
        CHOICE_INPUT = "choice".freeze
        NUMBER_INPUT = "number".freeze
        FOLLOW = "workflow_jobs with its run_id, or ci_status, follows it".freeze
        HISTORY_LIMIT = 20
        # A name filter is applied to GitHub's newest runs, so more are read to find enough of that workflow.
        HISTORY_CANDIDATES = 100
        # A run's status, or its conclusion once completed, in Firefight's words (the status and conclusion enums of a
        # workflow run in github/rest-api-description). action_required waits for someone to approve it.
        HISTORY_STATUSES = {
          "requested" => Capabilities::History::QUEUED, "queued" => Capabilities::History::QUEUED, "waiting" => Capabilities::History::QUEUED,
          "pending" => Capabilities::History::QUEUED, "action_required" => Capabilities::History::QUEUED,
          "in_progress" => Capabilities::History::RUNNING,
          "success" => Capabilities::History::SUCCEEDED, "neutral" => Capabilities::History::SUCCEEDED, "skipped" => Capabilities::History::SUCCEEDED,
          "failure" => Capabilities::History::FAILED, "timed_out" => Capabilities::History::FAILED, "startup_failure" => Capabilities::History::FAILED,
          "cancelled" => Capabilities::History::CANCELLED, "stale" => Capabilities::History::CANCELLED
        }.freeze

        def self.included(pack)
          pack.tool :list_workflows,
                    description: "A repository's GitHub Actions workflows, each with its file, whether it is active and its page. A " \
                                 "workflow's file name is what workflow_runs and run_workflow take",
                    params_schema: Code.object_schema({ "repo" => Code::REPO }, %w[repo]),
                    read_only: true

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

          pack.tool :ci_runs,
                    description: "A repository's GitHub Actions runs, newest first, each with its workflow, status, when it started and " \
                                 "finished and how long it took, and how long finished runs usually take",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO,
                      "name" => { "type" => "string", "description" => "Only runs of a workflow whose name contains this, such as release (optional)" },
                      "branch" => { "type" => "string", "description" => "Only runs for this branch (optional)" },
                      "run" => { "type" => "string", "description" => "Only this run, by its id, with each job and the step it failed at (optional)" },
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{HISTORY_LIMIT})" }
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

          run_id = { "type" => "integer", "description" => "The run's id, as workflow_runs or ci_status shows it" }
          pack.tool :rerun_workflow,
                    description: "Run a finished GitHub Actions workflow run again, every job or only the jobs that failed and the jobs " \
                                 "that depend on them, on the same commit. For a failure that is not the code, such as a flaky test",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO, "run_id" => run_id,
                      "failed_only" => { "type" => "boolean", "description" => "Only the failed jobs and the jobs that depend on them (optional, every job)" }
                    }, %w[repo run_id]),
                    read_only: false

          pack.tool :run_workflow,
                    description: "Start a GitHub Actions workflow by hand on a branch or tag, with the inputs it declares. Only a workflow " \
                                 "with a workflow_dispatch trigger can be started this way",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO,
                      "workflow" => { "type" => "string", "description" => "The workflow's file name, such as deploy.yml, or its id" },
                      "ref" => { "type" => "string", "description" => "The branch or tag to run it on (optional, the default branch)" },
                      "inputs" => { "type" => "object", "additionalProperties" => { "type" => "string" },
                                    "description" => "The workflow's inputs by name, each value as text, such as true or 3 (optional, the defaults it declares)" }
                    }, %w[repo workflow]),
                    read_only: false

          pack.tool :cancel_workflow,
                    description: "Cancel a GitHub Actions workflow run that is queued or running, such as a deploy that should not go out",
                    params_schema: Code.object_schema({ "repo" => Code::REPO, "run_id" => run_id }, %w[repo run_id]),
                    read_only: false
        end

        def list_workflows(environment_row:, arguments:)
          repo = repo_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          workflows = Array(GithubApp.get("/repos/#{repo}/actions/workflows?per_page=100", token: token)["workflows"])
          lines = workflows.map { |workflow| "  #{workflow['name']}  #{workflow['path']}  #{workflow['state'].to_s.tr('_', ' ')}  id #{workflow['id']}  #{workflow['html_url']}" }
          Telemetry.result(lines.empty? ? "#{repo} has no GitHub Actions workflows." : "Workflows in #{repo}:\n#{lines.join("\n")}",
                           link: actions_link("https://github.com/#{repo}/actions"))
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

        # GitHub gives a workflow run no completion time, so a finished run ended when it last changed, its updated_at.
        def ci_runs(environment_row:, arguments:)
          repo = repo_argument(arguments)
          return one_run(repo, GithubApp.installation_token(environment_row), arguments["run"]) if arguments["run"].present?

          limit = whole_number_argument(arguments, "limit", HISTORY_LIMIT, HISTORY_LIMIT)
          name = arguments["name"].to_s.strip.presence
          query = { "branch" => arguments["branch"].presence, "per_page" => name ? HISTORY_CANDIDATES : limit }
          runs = runs_of(repo, GithubApp.installation_token(environment_row), query).map { |run| history_run(run) }
          Capabilities::History.result(runs, what: "GitHub Actions in #{repo}", link: actions_link("https://github.com/#{repo}/actions"), name: name, limit: limit)
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

        def rerun_workflow(environment_row:, arguments:)
          repo = repo_argument(arguments)
          id = run_id_argument(arguments)
          failed_only = ActiveModel::Type::Boolean.new.cast(arguments["failed_only"]) || false
          token = GithubApp.installation_token(environment_row)
          run = GithubApp.get("/repos/#{repo}/actions/runs/#{id}", token: token)
          fail! "#{run_name(run, repo)} is still #{run['status']}, so it cannot run again until it finishes. cancel_workflow stops it." unless run["status"] == COMPLETED
          if failed_only && run["conclusion"] == SUCCESS
            fail! "#{run_name(run, repo)} passed, so it has no failed jobs to run again. Leave failed_only off to run every job again."
          end

          changing("run #{repo} run #{id} again") { GithubApp.act("/repos/#{repo}/actions/runs/#{id}/#{failed_only ? 'rerun-failed-jobs' : 'rerun'}", {}, token: token) }
          what = failed_only ? "its failed jobs and the jobs that depend on them" : "every job"
          Telemetry.result("#{run_name(run, repo)} runs again as attempt #{run['run_attempt'].to_i + 1}, #{what}, on #{run['head_branch']} at " \
                           "#{run['head_sha'].to_s[0, 12]}. #{FOLLOW}.", link: actions_link(run["html_url"]))
        end

        def run_workflow(environment_row:, arguments:)
          repo = repo_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          workflow = GithubApp.get("/repos/#{repo}/actions/workflows/#{workflow_argument(arguments)}", token: token)
          name = "#{workflow['name']} (#{workflow['path']})"
          fail! "#{name} in #{repo} is #{workflow['state'].to_s.tr('_', ' ')}, so it cannot be started. A person enables it in GitHub." unless workflow["state"] == ACTIVE

          default_branch = GithubApp.get("/repos/#{repo}", token: token)["default_branch"]
          ref = ref_argument(arguments) || default_branch
          # GitHub starts a workflow by hand only when its file on the default branch has the trigger, and runs the file at ref.
          dispatch = dispatch_of(workflow_file(repo, workflow["path"], default_branch, token))
          fail! "#{name} has no #{DISPATCH} trigger on #{default_branch}, so it cannot be started by hand. It runs on the events it names." unless dispatch

          declared = ref == default_branch ? dispatch : dispatch_of(workflow_file(repo, workflow["path"], ref, token)) || dispatch
          inputs = inputs_for(declared, arguments["inputs"], name)
          started = changing("start #{name} in #{repo}") do
            GithubApp.act("/repos/#{repo}/actions/workflows/#{workflow['id']}/dispatches", { ref: ref, inputs: inputs, return_run_details: true }.compact_blank, token: token)
          end
          given = inputs.any? ? " with #{inputs.map { |key, value| "#{key} #{value}" }.join(', ')}" : ""
          run = started.is_a?(Hash) ? started["workflow_run_id"] : nil
          return "Started #{name} on #{ref} in #{repo}#{given}. GitHub did not say which run it is, so workflow_runs with event #{DISPATCH} finds it." unless run

          Telemetry.result("Started #{name} on #{ref} in #{repo}#{given}, as run #{run}. #{FOLLOW}.", link: actions_link(started["html_url"]))
        end

        def cancel_workflow(environment_row:, arguments:)
          repo = repo_argument(arguments)
          id = run_id_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          run = GithubApp.get("/repos/#{repo}/actions/runs/#{id}", token: token)
          fail! "#{run_name(run, repo)} already finished, #{outcome(run)}, so there is nothing to cancel." if run["status"] == COMPLETED

          changing("cancel #{repo} run #{id}") { GithubApp.act("/repos/#{repo}/actions/runs/#{id}/cancel", token: token) }
          Telemetry.result("Canceling #{run_name(run, repo)} on #{run['head_branch']} at #{run['head_sha'].to_s[0, 12]}. A job or step whose if " \
                           "condition holds, such as always(), keeps running, and GitHub stops the rest within 5 minutes. #{FOLLOW}.", link: actions_link(run["html_url"]))
        end

        # Whoever triggered the run, matched to a member by the public address GitHub shows for them. A run a bot started
        # has nobody to ask.
        def owner_of(tool_name, environment_row:, arguments:)
          return super unless tool_name == "cancel_workflow"

          repo = repo_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          run = GithubApp.get("/repos/#{repo}/actions/runs/#{run_id_argument(arguments)}", token: token)
          login = (run["triggering_actor"] || run["actor"]).to_h["login"].to_s
          return if login.empty? || login.end_with?("[bot]")

          Owner.new(name: login, email: GithubApp.get("/users/#{Http.segment(login)}", token: token)["email"], role: Owner::ROLE_STARTED,
                    what: run_name(run, repo))
        end

        private

        # A change GitHub refused for the permission it needs is said with the permission, so a person knows what to grant.
        def changing(what)
          yield
        rescue GithubApp::NotPermitted => error
          fail! Sentence.join("GitHub refused to #{what}", error, after: "Firefight's GitHub App needs the #{WRITE_PERMISSION} permission " \
                                                                          "on this installation for that. #{Asking::GRANT_WHERE}")
        end

        def history_run(run)
          status = Capabilities::History.status(outcome(run), HISTORY_STATUSES)
          Capabilities::History::Run.new(
            id: run["id"].to_s, number: run["run_number"]&.to_s, name: run["name"], status: status,
            started_at: Telemetry.parse_time(run["run_started_at"] || run["created_at"]),
            finished_at: (Telemetry.parse_time(run["updated_at"]) if Capabilities::History::FINISHED.include?(status)),
            url: run["html_url"], detail: "#{run['head_branch']} at #{run['head_sha'].to_s[0, 12]}, #{run['event']}"
          )
        end

        # One run with its jobs, each failed one with the step it failed at and its log read by job_log, so a watch hears
        # the first job that failed while the run still goes.
        def one_run(repo, token, given)
          id = Integer(given.to_s.strip.delete_prefix("#"), exception: false)
          fail! "run must be the run's id, a whole number" unless id&.positive?

          run = GithubApp.get("/repos/#{repo}/actions/runs/#{id}", token: token)
          parts = jobs_of(repo, id, token).map { |job| history_part(repo, job) }
          Capabilities::History.result([ history_run(run).with(parts: parts) ], what: "GitHub Actions in #{repo}", link: actions_link(run["html_url"]))
        end

        def history_part(repo, job)
          status = Capabilities::History.status(outcome(job), HISTORY_STATUSES)
          failed = Array(job["steps"]).find { |step| FAILED_CONCLUSIONS.include?(step["conclusion"]) }&.dig("name")
          Capabilities::History::Part.new(
            id: job["id"].to_s, name: job["name"], status: status, started_at: Telemetry.parse_time(job["started_at"]),
            finished_at: (Telemetry.parse_time(job["completed_at"]) if Capabilities::History::FINISHED.include?(status)),
            url: job["html_url"], detail: failed && "at #{failed}",
            log: { Capabilities::History::LOG_TOOL => "job_log", Capabilities::History::LOG_ARGUMENTS => { "repo" => repo, "job_id" => job["id"] } }
          )
        end

        def run_name(run, repo) = "#{run['name']} run #{run['run_number']} (#{run['id']}) in #{repo}"

        def run_id_argument(arguments)
          id = Integer(arguments["run_id"].to_s, exception: false)
          fail! "run_id must be a whole number" unless id&.positive?

          id
        end

        def workflow_argument(arguments)
          given = File.basename(arguments["workflow"].to_s.strip)
          fail! "workflow must be the workflow's file name, such as deploy.yml, or its id" unless given.match?(/\A\d+\z/) || given.match?(WORKFLOW_FILE)

          Http.segment(given)
        end

        def workflow_file(repo, path, ref, token)
          YAML.safe_load(read_file_lines(repo, path, ref, token).join, aliases: true)
        rescue Psych::Exception => error
          fail! Sentence.join("#{path} on #{ref} could not be read as YAML", error)
        end

        # What the workflow's workflow_dispatch trigger declares, {} when it declares nothing, or nil without one. YAML reads
        # a bare on as true, so the key is either.
        def dispatch_of(document)
          triggers = document.is_a?(Hash) ? (document.key?("on") ? document["on"] : document[true]) : nil
          case triggers
          when String then triggers == DISPATCH ? {} : nil
          when Array then triggers.include?(DISPATCH) ? {} : nil
          when Hash then triggers.key?(DISPATCH) ? (triggers[DISPATCH].is_a?(Hash) ? triggers[DISPATCH] : {}) : nil
          end
        end

        # The inputs given, checked against what the workflow declares, each as text, which GitHub takes for every type.
        def inputs_for(dispatch, given, name)
          declared = dispatch["inputs"].is_a?(Hash) ? dispatch["inputs"] : {}
          fail! "inputs must be an object of names and values" unless given.nil? || given.is_a?(Hash)

          given = (given || {}).transform_keys(&:to_s).transform_values(&:to_s)
          unknown = given.keys - declared.keys
          if unknown.any?
            fail! "#{name} declares no #{'input'.pluralize(unknown.size)} #{unknown.to_sentence}. " \
                  "#{declared.any? ? "It declares #{declared.keys.to_sentence}." : 'It declares no inputs.'}"
          end

          missing = declared.select { |key, spec| spec.is_a?(Hash) && spec["required"] && spec["default"].nil? && !given.key?(key) }.keys
          fail! "#{name} needs #{'input'.pluralize(missing.size)} #{missing.to_sentence}, which #{missing.one? ? 'has' : 'have'} no default." if missing.any?

          given.each { |key, value| check_input!(key, value, declared[key]) }
          given
        end

        def check_input!(key, value, spec)
          return unless spec.is_a?(Hash)

          case spec["type"]
          when BOOLEAN_INPUT then fail!("#{key} must be true or false") unless %w[true false].include?(value)
          when NUMBER_INPUT then fail!("#{key} must be a number") unless Float(value, exception: false)
          when CHOICE_INPUT
            options = Array(spec["options"]).map(&:to_s)
            fail!("#{key} must be one of #{options.join(', ')}") unless options.include?(value)
          end
        end

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
