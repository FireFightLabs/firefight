module Integrations
  module Packs
    class Circleci
      # A project's runs as CircleCI's API v3 keeps them (runs.md, workflows.md, jobs.md, test-results.md): a run is one
      # firing of a trigger, holding workflows, each holding jobs, each holding steps whose output is read one step at a
      # time. A run's phase is queued, started or ended, and how it ended is its current_outcome: succeeded, failed,
      # canceled, errored, not_run or unauthorized (runs.md, GET /api/v3/runs/:id). Workflows and jobs carry a phase and
      # an outcome the same way.
      module Runs
        RUN_LIMIT = 10
        MOST_RUNS = CircleciApi::RUN_PAGE
        STREAK = 10
        # The newest runs a failed job is looked for in when none is named.
        FAILED_JOB_RUNS = 10
        PHASES = { "queued" => Capabilities::History::QUEUED, "started" => Capabilities::History::RUNNING }.freeze
        OUTCOMES = {
          "succeeded" => Capabilities::History::SUCCEEDED, "failed" => Capabilities::History::FAILED, "errored" => Capabilities::History::FAILED,
          "unauthorized" => Capabilities::History::FAILED, "canceled" => Capabilities::History::CANCELLED, "not_run" => Capabilities::History::CANCELLED
        }.freeze
        ENDED = "ended".freeze
        # A step or test that did not pass, in the words CircleCI writes, or a step that exited with a code other than 0.
        FAILING = /fail|error|timed/i
        APPROVAL = "approval".freeze

        def self.included(pack)
          project = Circleci::PROJECT_PARAM
          repository = Circleci::REPOSITORY_PARAM
          run = { "type" => "string", "description" => "A run's id, as list_runs or ci_runs shows it" }
          workflow = { "type" => "string", "description" => "A workflow's id, as get_run or list_workflows shows it" }
          job = { "type" => "string", "description" => "A job's id, as list_jobs or get_run shows it" }
          branch = { "type" => "string", "description" => "Only runs on this branch (optional)" }

          pack.tool :list_runs,
                    summary: "Lists recent pipeline runs for a project.",
                    description: "A project's runs, newest first, each with its number, id, how it stands, its workflows, the branch and commit " \
                                 "it built and what started it. Filter by branch or by how it ended",
                    params_schema: { "type" => "object", "properties" => {
                      "project" => project, Capabilities::Circleci::REPOSITORY => repository, "branch" => branch,
                      "status" => { "type" => "string", "enum" => Capabilities::History::STATUSES, "description" => "Only runs that stand this way (optional)" },
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{RUN_LIMIT}, at most #{MOST_RUNS})" }
                    } },
                    read_only: true

          pack.tool :get_run,
                    summary: "Shows one pipeline run with its status and trigger.",
                    description: "One run: how it stands, what started it, the branch, tag and commit it built, any config errors that kept its " \
                                 "workflows from starting, and its workflows with their jobs",
                    params_schema: { "type" => "object", "properties" => { "run" => run }, "required" => %w[run] },
                    read_only: true

          pack.tool :list_workflows,
                    summary: "Lists the workflows in a pipeline run.",
                    description: "The workflows of one run, newest first, each with its id, how it stands and when it started and ended",
                    params_schema: { "type" => "object", "properties" => { "run" => run }, "required" => %w[run] },
                    read_only: true

          pack.tool :get_workflow,
                    summary: "Shows one workflow with its status and timing.",
                    description: "One workflow: how it stands, when it started and ended, whether it was rerun automatically, and its page",
                    params_schema: { "type" => "object", "properties" => { "workflow" => workflow }, "required" => %w[workflow] },
                    read_only: true

          pack.tool :list_jobs,
                    summary: "Lists the jobs in a workflow.",
                    description: "The jobs of one workflow, each with its id, number, type (a build or an approval), how it stands and how long it took",
                    params_schema: { "type" => "object", "properties" => { "workflow" => workflow }, "required" => %w[workflow] },
                    read_only: true

          pack.tool :get_job,
                    summary: "Shows one job with its status and duration.",
                    description: "One job with each of its steps, per parallel execution: how each ended, its exit code and how long it took. " \
                                 "get_job_logs reads a step's output",
                    params_schema: { "type" => "object", "properties" => { "job" => job }, "required" => %w[job] },
                    read_only: true

          pack.tool :get_job_logs,
                    summary: "Shows the build output of a job.",
                    description: "The end of what a job's steps printed, the steps that failed unless one is named, filtered by text if asked. " \
                                 "Without a job, the newest failed job of a project's newest runs, in one run, on a branch or in the time asked",
                    params_schema: { "type" => "object", "properties" => {
                      "job" => job.merge("description" => "#{job['description']} (optional, with project instead)"),
                      "project" => project.merge("description" => "#{project['description']} (optional, with job instead)"),
                      Capabilities::Circleci::REPOSITORY => repository,
                      "run" => { "type" => "string", "description" => "Only a job of this run, by its id, when no job is named (optional)" },
                      "branch" => { "type" => "string", "description" => "Only a job of a run on this branch, when no job is named (optional)" },
                      "step" => { "type" => "string", "description" => "Only this step, by its name (optional, the steps that failed)" },
                      **CodeHost::LOG_FILTER, **CodeHost::LOG_RANGE
                    } },
                    read_only: true

          pack.tool :list_artifacts,
                    summary: "Lists the files a job saved as artifacts.",
                    description: "The files one job saved as artifacts, per parallel execution, with each one's path and address",
                    params_schema: { "type" => "object", "properties" => { "job" => job }, "required" => %w[job] },
                    read_only: true

          pack.tool :list_job_tests,
                    summary: "Lists a job's test results, including failures.",
                    description: "The tests one job ran, the ones that failed unless all are asked, each with its class, file, how long it took and its message",
                    params_schema: { "type" => "object", "properties" => {
                      "job" => job, "all" => { "type" => "boolean", "description" => "Every test, not only those that failed (optional)" }
                    }, "required" => %w[job] },
                    read_only: true

          pack.tool :ci_runs,
                    summary: "Lists recent runs with how long each took compared with the usual time.",
                    description: "A project's runs, newest first, each with how it stands, when it started and finished and how long it took, and " \
                                 "how long finished runs usually take. With run, that one run with each job of its workflows and how it ended",
                    params_schema: { "type" => "object", "properties" => {
                      "project" => project, Capabilities::Circleci::REPOSITORY => repository,
                      "name" => { "type" => "string", "description" => "Only runs with a workflow whose name contains this, such as deploy (optional)" },
                      "branch" => branch,
                      "run" => { "type" => "string", "description" => "Only this run, by its id, with each job and how it ended (optional)" },
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{RUN_LIMIT}, at most #{MOST_RUNS})" }
                    } },
                    read_only: true

          pack.tool :ci_status,
                    summary: "Shows how CI stands on a branch, its failed jobs and what is deployed.",
                    description: "How a project's CI stands now: its newest run on a branch (the default branch unless named) with its workflows " \
                                 "and failed jobs, how its last runs went and since when it fails, and what each deploy component runs in each environment",
                    params_schema: { "type" => "object", "properties" => {
                      "project" => project, Capabilities::Circleci::REPOSITORY => repository,
                      "branch" => { "type" => "string", "description" => "The branch (optional, the project's default branch)" }
                    } },
                    read_only: true
        end

        def list_runs(environment_row:, arguments:)
          project = find_project(environment_row, arguments)
          limit = whole_number_argument(arguments, "limit", RUN_LIMIT, MOST_RUNS)
          status = arguments["status"].presence
          fail! "status must be one of #{Capabilities::History::STATUSES.join(', ')}" if status && Capabilities::History::STATUSES.exclude?(status)

          runs = on_branch(api(environment_row).runs(project.id), arguments["branch"])
          runs = runs.select { |run| history_run(environment_row, project, run).status == status } if status
          link = project_link(environment_row, project)
          return Telemetry.result("No runs of #{project.label} match.", link: link) if runs.empty?

          lines = runs.first(limit).map { |run| run_line(run) }
          Telemetry.result("Newest #{lines.size} runs of #{project.label}. get_run reads one with its workflows.\n#{lines.join("\n")}", link: link)
        end

        def get_run(environment_row:, arguments:)
          run = read_run(environment_row, id_argument(arguments, "run"))
          workflows = workflows_of(environment_row, run)
          lines = [ run_line(run), *errors_of(run), *workflows.map { |workflow| "  #{workflow_line(workflow)}" } ]
          lines << "  No workflow started, so the problem is the config or the trigger, not the code." if workflows.empty?
          Telemetry.result(lines.join("\n"), link: workflow_link(environment_row, workflows.first))
        end

        def list_workflows(environment_row:, arguments:)
          run = id_argument(arguments, "run")
          workflows = api(environment_row).workflows(run)
          return Telemetry.result("Run #{run} has no workflows.", link: nil) if workflows.empty?

          Telemetry.result("#{workflows.size} workflows of run #{run}:\n#{workflows.map { |workflow| workflow_line(workflow) }.join("\n")}",
                           link: workflow_link(environment_row, workflows.first))
        end

        def get_workflow(environment_row:, arguments:)
          workflow = read_workflow(environment_row, id_argument(arguments, "workflow"))
          rerun = workflow.dig("attributes", "auto_rerun")
          lines = [ workflow_line(workflow), ("Rerun automatically, #{rerun['number']} of #{rerun['max_reruns']}" if rerun) ].compact
          Telemetry.result(lines.join("\n"), link: workflow_link(environment_row, workflow))
        end

        def list_jobs(environment_row:, arguments:)
          workflow = id_argument(arguments, "workflow")
          jobs = api(environment_row).jobs(workflow)
          link = workflow_link(environment_row, { "id" => workflow })
          return Telemetry.result("Workflow #{workflow} has no jobs.", link: link) if jobs.empty?

          Telemetry.result("#{jobs.size} jobs of workflow #{workflow}:\n#{jobs.map { |job| job_line(job) }.join("\n")}", link: link)
        end

        def get_job(environment_row:, arguments:)
          job = read_job(environment_row, id_argument(arguments, "job"))
          executions = Array(job.dig("attributes", "parallel_executions"))
          lines = [ job_line(job) ]
          executions.each_with_index do |execution, index|
            lines << "Parallel execution #{index}:" if executions.many?
            lines.concat(Array(execution["steps"]).map { |step| "  #{step_line(step)}" })
          end
          lines << "No steps were recorded." if executions.empty?
          Telemetry.result(lines.join("\n"), link: workflow_link(environment_row, { "id" => job.dig("references", "workflow", "id") }))
        end

        def get_job_logs(environment_row:, arguments:)
          job = if arguments["job"].present?
            read_job(environment_row, id_argument(arguments, "job"))
          else
            newest_failed_job(environment_row, find_project(environment_row, arguments), arguments)
          end
          return Telemetry.result(no_failed_job(arguments), link: nil) unless job

          name = job.dig("attributes", "name")
          heading = "Job #{name} (#{job['id']}), #{state_words(job['attributes'])}, ended #{job.dig('attributes', 'ended_at') || 'not yet'}."
          printed = steps_printed(environment_row, job, arguments["step"].to_s.strip.presence)
          link = workflow_link(environment_row, { "id" => job.dig("references", "workflow", "id") })
          return Telemetry.result("#{heading}\nCircleCI kept no output for its steps.", link: link) if printed.blank?

          kept, matched = build_log_lines(printed, arguments)
          Telemetry.result(log_text(heading, kept, matched), link: link)
        end

        def list_artifacts(environment_row:, arguments:)
          job = id_argument(arguments, "job")
          artifacts = api(environment_row).artifacts(job)
          return Telemetry.result("Job #{job} saved no artifacts.", link: nil) if artifacts.empty?

          lines = artifacts.map { |artifact| "#{artifact.dig('attributes', 'path')} (execution #{artifact.dig('attributes', 'execution')}): #{artifact.dig('attributes', 'url')}" }
          Telemetry.result("#{lines.size} artifacts of job #{job}:\n#{lines.join("\n")}", link: nil)
        end

        def list_job_tests(environment_row:, arguments:)
          job = id_argument(arguments, "job")
          read = api(environment_row).test_results(job)
          all = ActiveModel::Type::Boolean.new.cast(arguments["all"])
          tests = read.items.map { |result| result["attributes"].to_h }
          shown = all ? tests : tests.select { |test| test["outcome"].to_s.match?(FAILING) }
          cut = read.incomplete? ? " Only the first #{tests.size} results were read." : ""
          return Telemetry.result("Job #{job} ran #{tests.size} tests and none failed.#{cut}", link: nil) if shown.empty?

          lines = shown.map do |test|
            [ "#{test['classname']} #{test['name']}".strip, test["outcome"], ("#{test['duration_ms']}ms" if test["duration_ms"]), test["file"].presence,
              ("rerun #{test['rerun_attempt']}" if test["rerun_attempt"].to_i.positive?), test["message"].to_s.lines.first(3).join.strip.presence ].compact.join(", ")
          end
          Telemetry.result("#{shown.size} of #{tests.size} tests of job #{job}#{' failed' unless all}.#{cut}\n#{lines.join("\n")}", link: nil)
        end

        def ci_runs(environment_row:, arguments:)
          project = find_project(environment_row, arguments)
          return one_run(environment_row, project, arguments["run"].to_s.strip) if arguments["run"].present?

          limit = whole_number_argument(arguments, "limit", RUN_LIMIT, MOST_RUNS)
          runs = on_branch(api(environment_row).runs(project.id), arguments["branch"]).map { |run| history_run(environment_row, project, run) }
          Capabilities::History.result(runs, what: project.label, link: project_link(environment_row, project), name: arguments["name"], limit: limit)
        end

        def ci_status(environment_row:, arguments:)
          project = find_project(environment_row, arguments)
          branch = arguments["branch"].to_s.strip.presence || project.branch
          recent = on_branch(api(environment_row).runs(project.id, limit: STREAK), branch)
          latest = recent.first
          sections = [ latest_text(environment_row, project, branch, latest), streak_text(recent), deployed_text(environment_row, project) ].compact
          Telemetry.result(sections.join("\n\n"), link: (latest && workflow_link(environment_row, workflows_of(environment_row, latest).first)) || project_link(environment_row, project))
        end

        private

        def id_argument(arguments, key) = arguments[key].to_s.strip.presence || fail!("Say which #{key}, by the id CircleCI gives it.")

        def read_run(environment_row, id)
          api(environment_row).run(id)["data"].to_h
        rescue CircleciApi::NotFound
          fail!("CircleCI has no run #{id} this token can see.")
        end

        def read_workflow(environment_row, id)
          api(environment_row).workflow(id)["data"].to_h
        rescue CircleciApi::NotFound
          fail!("CircleCI has no workflow #{id} this token can see.")
        end

        def read_job(environment_row, id)
          api(environment_row).job(id)["data"].to_h
        rescue CircleciApi::NotFound
          fail!("CircleCI has no job #{id} this token can see.")
        end

        # A run's workflows, as a list of runs carries them (each one's fields at its top, its jobs inside) or read on their
        # own, each with its fields under attributes either way.
        def workflows_of(environment_row, run)
          listed = run.dig("attributes", "workflows", "items")
          if listed.is_a?(Array) && !run.dig("attributes", "workflows", "is_truncated")
            return listed.map { |workflow| { "id" => workflow["id"], "attributes" => workflow } }
          end

          api(environment_row).workflows(run["id"])
        end

        def vcs_of(run) = run.dig("references", "event", "attributes", "vcs").to_h

        def on_branch(runs, branch)
          wanted = branch.to_s.strip
          wanted.empty? ? runs : runs.select { |run| vcs_of(run)["branch"] == wanted }
        end

        def status_of(attributes)
          attributes = attributes.to_h
          phase = attributes["phase"].to_s
          outcome = attributes["current_outcome"].presence || attributes["outcome"]
          return Capabilities::History.status(outcome, OUTCOMES) if phase == ENDED

          PHASES.fetch(phase, Capabilities::History::RUNNING)
        end

        def state_words(attributes)
          attributes = attributes.to_h
          [ attributes["phase"], attributes["current_outcome"].presence || attributes["outcome"] ].compact_blank.join(", ")
        end

        def run_line(run)
          attributes = run["attributes"].to_h
          vcs = vcs_of(run)
          workflows = Array(attributes.dig("workflows", "items")).map { |workflow| "#{workflow['name']} (#{status_of(workflow)})" }
          [ "##{attributes['number']} run #{run['id']}", state_words(attributes), attributes["created_at"],
            (vcs["branch"] ? "branch #{vcs['branch']}" : ("tag #{vcs['tag']}" if vcs["tag"])), ("commit #{vcs['revision'].to_s.first(12)}" if vcs["revision"]),
            (vcs.dig("commit", "subject").to_s.lines.first.to_s.strip.presence&.then { |subject| "\"#{subject}\"" }),
            run.dig("references", "trigger", "attributes", "event_source", "type")&.then { |type| "started by #{type}" },
            ("workflows #{workflows.join(', ')}" if workflows.any?) ].compact.join(", ")
        end

        def errors_of(run)
          Array(run.dig("attributes", "errors")).map { |error| "  Error (#{error['type']}): #{error['message']}" }
        end

        def workflow_line(workflow)
          attributes = workflow["attributes"].to_h
          [ "workflow #{attributes['name']} (#{workflow['id']})", state_words(attributes), ("started #{attributes['created_at']}" if attributes["created_at"]),
            ("ended #{attributes['ended_at']}" if attributes["ended_at"]) ].compact.join(", ")
        end

        def job_line(job)
          attributes = job["attributes"].to_h
          took = seconds_between(attributes["started_at"], attributes["ended_at"])
          [ "#{attributes['name']} (#{job['id']}#{", ##{attributes['number']}" if attributes['number']})", attributes["type"], state_words(attributes),
            ("took #{took}s" if took) ].compact.join(", ")
        end

        def step_line(step)
          took = seconds_between(step["started_at"], step["ended_at"])
          [ "#{step['num']}. #{step['name']}", state_words(step), ("exit code #{step['exit_code']}" unless step["exit_code"].nil?), ("took #{took}s" if took) ].compact.join(", ")
        end

        def seconds_between(started, ended)
          from, to = Telemetry.parse_time(started), Telemetry.parse_time(ended)
          (to - from).round if from && to
        end

        def failing_step?(step) = step["outcome"].to_s.match?(FAILING) || step["exit_code"].to_i != 0

        # What the chosen steps printed, stdout then stderr, each headed by its step and execution. The steps are the one
        # named, or else those that failed, or else the last, which is where a job that did not fail says how it ended.
        def steps_printed(environment_row, job, named)
          executions = Array(job.dig("attributes", "parallel_executions"))
          chosen = executions.each_with_index.flat_map do |execution, index|
            steps = Array(execution["steps"])
            picked = named ? steps.select { |step| step["name"].to_s.casecmp?(named) } : steps.select { |step| failing_step?(step) }
            picked = [ steps.last ].compact if picked.empty? && named.nil?
            picked.map { |step| [ index, step ] }
          end
          fail! "Job #{job['id']} has no step called #{named}. get_job lists its steps." if named && chosen.empty?

          chosen.map do |index, step|
            streams = %w[stdout stderr].select { |stream| stream == "stdout" || step["#{stream}_bytes"].to_i.positive? }
            printed = streams.map { |stream| api(environment_row).step_output(job["id"], step: step["num"], execution: index, stream: stream) }.join("\n")
            "== #{step['name']}#{" (execution #{index})" if executions.many?} ==\n#{printed}"
          end.join("\n")
        end

        # The newest job that failed in a project's newest runs, in the run, on the branch and in the time asked.
        def newest_failed_job(environment_row, project, arguments)
          started, ended = Telemetry.range(arguments, default_minutes: CodeHost::LOG_RANGE_MINUTES, max_minutes: CodeHost::LOG_RANGE_MINUTES) if ranged?(arguments)
          runs = if arguments["run"].present? then [ read_run(environment_row, arguments["run"].to_s.strip) ]
          else on_branch(api(environment_row).runs(project.id, limit: FAILED_JOB_RUNS), arguments["branch"])
          end
          runs.each do |run|
            workflows_of(environment_row, run).each do |workflow|
              next unless status_of(workflow["attributes"]) == Capabilities::History::FAILED

              failed = api(environment_row).jobs(workflow["id"]).select do |job|
                ended_at = Telemetry.parse_time(job.dig("attributes", "ended_at"))
                status_of(job["attributes"]) == Capabilities::History::FAILED && (started.nil? || (ended_at && ended_at.between?(started, ended)))
              end
              newest = failed.max_by { |job| job.dig("attributes", "ended_at").to_s }
              return read_job(environment_row, newest["id"]) if newest
            end
          end
          nil
        end

        def ranged?(arguments) = %w[minutes start end].any? { |key| arguments[key].present? }

        def no_failed_job(arguments)
          where = [ ("in run #{arguments['run']}" if arguments["run"].present?), ("on #{arguments['branch']}" if arguments["branch"].present?),
                    ("in that time" if ranged?(arguments)) ].compact.join(" ")
          "No failed job#{" #{where}" if where.present?} among the project's newest #{FAILED_JOB_RUNS} runs."
        end

        # A run from when it was made until its last workflow ended, named by its workflows. A run in a list links its
        # project's pipelines page, and one read on its own its workflow's page, built from the slug and pipeline number
        # CircleCI gives the workflow (v2 getWorkflowById), as a webhook's workflow url is.
        def history_run(environment_row, project, run, workflows: nil, url: nil)
          attributes = run["attributes"].to_h
          workflows ||= Array(attributes.dig("workflows", "items"))
          status = status_of(attributes)
          ended = workflows.filter_map { |workflow| Telemetry.parse_time((workflow["attributes"] || workflow)["ended_at"]) }.max
          vcs = vcs_of(run)
          Capabilities::History::Run.new(
            id: run["id"].to_s, number: attributes["number"]&.to_s, name: workflows.map { |workflow| (workflow["attributes"] || workflow)["name"] }.compact.uniq.join(", ").presence || "run",
            status: status, started_at: Telemetry.parse_time(attributes["created_at"]), finished_at: (ended if Capabilities::History::FINISHED.include?(status)),
            url: url || self.class.page(site(environment_row), project.slug),
            detail: [ ("#{vcs['branch'] || vcs['tag']} at #{vcs['revision'].to_s.first(12)}" if vcs["revision"]), *Array(attributes["errors"]).map { |error| error["message"] } ].compact.join(", ").presence
          )
        end

        # One run, read by its id however old it is, with every job of its workflows as a part, each read by get_job_logs.
        # An approval job has no output, so it has no log.
        def one_run(environment_row, project, id)
          run = read_run(environment_row, id)
          fail! "Run #{id} is another project's, not #{project.label}'s." if run.dig("references", "project", "id").present? && run.dig("references", "project", "id") != project.id

          workflows = api(environment_row).workflows(id)
          pages = workflows.to_h { |workflow| [ workflow["id"], workflow_link(environment_row, workflow)&.url ] }
          parts = workflows.flat_map do |workflow|
            api(environment_row).jobs(workflow["id"]).map { |job| history_part(job, workflow, pages[workflow["id"]]) }
          end
          history = history_run(environment_row, project, run, workflows: workflows, url: pages.values.compact.first).with(parts: parts)
          Capabilities::History.result([ history ], what: project.label, link: link_to(history.url) || project_link(environment_row, project))
        end

        def history_part(job, workflow, page)
          attributes = job["attributes"].to_h
          approval = attributes["type"] == APPROVAL
          Capabilities::History::Part.new(
            id: job["id"].to_s, name: "#{workflow.dig('attributes', 'name')} / #{attributes['name']}", status: status_of(attributes),
            started_at: Telemetry.parse_time(attributes["started_at"]), finished_at: Telemetry.parse_time(attributes["ended_at"]),
            url: page,
            detail: (approval ? "an approval, which approve_job gives" : nil),
            log: (approval ? nil : { Capabilities::History::LOG_TOOL => "get_job_logs", Capabilities::History::LOG_ARGUMENTS => { "job" => job["id"].to_s } })
          )
        end

        def latest_text(environment_row, project, branch, latest)
          where = branch ? "on #{branch}" : "of #{project.label}"
          return "No run #{where} among its newest #{STREAK}." unless latest

          text = "Newest run #{where}: #{run_line(latest)}"
          workflows = workflows_of(environment_row, latest)
          failed = workflows.select { |workflow| status_of(workflow["attributes"]) == Capabilities::History::FAILED }.flat_map do |workflow|
            api(environment_row).jobs(workflow["id"]).select { |job| status_of(job["attributes"]) == Capabilities::History::FAILED }.map { |job| "  #{workflow.dig('attributes', 'name')} / #{job_line(job)}" }
          end
          held = workflows.flat_map do |workflow|
            Array(workflow.dig("attributes", "jobs", "items")).select { |job| job["type"] == APPROVAL && job["phase"].to_s != ENDED }.map { |job| "  #{workflow.dig('attributes', 'name')} / #{job['name']} waits for approval" }
          end
          [ text, *errors_of(latest), ("Failed jobs:\n#{failed.join("\n")}\nget_job_logs with a job reads why." if failed.any?), *held ].compact.join("\n")
        end

        # When the branch last passed, so a failure that began a while ago reads differently from a new one.
        def streak_text(recent)
          return if recent.size < 2

          statuses = recent.map { |run| status_of(run["attributes"]) }
          passed = recent.find { |run| status_of(run["attributes"]) == Capabilities::History::SUCCEEDED }
          since = if status_of(recent.first["attributes"]) == Capabilities::History::FAILED
            passed ? " It last passed in run ##{passed.dig('attributes', 'number')} at #{passed.dig('attributes', 'created_at')}." : " None of these passed."
          end
          "The last #{recent.size} runs, newest first: #{statuses.join(', ')}.#{since}"
        end

        def workflow_link(environment_row, workflow)
          return unless workflow && workflow["id"].present?

          summary = api(environment_row).workflow_summary(workflow["id"])
          link_to(self.class.page(site(environment_row), summary["project_slug"], number: summary["pipeline_number"], workflow: workflow["id"]))
        rescue CircleciApi::Error
          nil
        end
      end
    end
  end
end
