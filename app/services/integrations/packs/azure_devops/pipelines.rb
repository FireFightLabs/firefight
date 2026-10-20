module Integrations
  module Packs
    class AzureDevops
      # A project's CI as Azure Pipelines keeps it: its runs (the Build API's builds, which every YAML and classic
      # pipeline run is), a run's stages and jobs from its timeline, a job's log, and how a branch stands now. A run is
      # read through the repository it built or the pipeline that ran it (Builds - List, Builds - Get, Timeline - Get,
      # Builds - Get Build Log). Running a pipeline, retrying a run's failed jobs, canceling a run and answering an
      # approval are changes (Runs - Run Pipeline, Builds - Queue, Builds - Update Build, Approvals - Update), so they go
      # through the gateway as writes and a member needs a grant for them.
      module Pipelines
        PIPELINE_PARAM = { "type" => "string", "description" => "A pipeline as project/pipeline, by its id or name, e.g. Shop/12 or Shop/checkout-ci" }.freeze
        PROJECT_PARAM = { "type" => "string", "description" => "The project the run is in, e.g. Shop" }.freeze
        BUILD_PARAM = { "type" => "integer", "description" => "The run's id, as pipelines, ci_runs or ci_status shows it" }.freeze
        RUN_LIMIT = 10
        MAX_RUNS = 50
        HISTORY_LIMIT = 10
        MAX_HISTORY = 20
        STREAK = 10
        FAILED_CANDIDATES = 25
        APPROVALS_SHOWN = 50
        RESULTS = %w[succeeded partiallySucceeded failed canceled].freeze
        COMPLETED = "completed".freeze
        SUCCEEDED = "succeeded".freeze
        JOB = "Job".freeze
        TASK = "Task".freeze
        PENDING = "pending".freeze
        DECISIONS = { "approve" => "approved", "reject" => "rejected" }.freeze
        # A YAML pipeline's process type, which the Pipelines API runs. A classic one is queued as a build.
        YAML_PROCESS = 2
        # A run's status in Firefight's words, its result once completed and its status before (BuildStatus, BuildResult).
        # A partly succeeded run finished its work with a step allowed to fail, as Azure DevOps' own page shows it.
        RUN_STATUSES = {
          "notstarted" => Capabilities::History::QUEUED, "postponed" => Capabilities::History::QUEUED,
          "inprogress" => Capabilities::History::RUNNING, "cancelling" => Capabilities::History::RUNNING,
          "succeeded" => Capabilities::History::SUCCEEDED, "partiallysucceeded" => Capabilities::History::SUCCEEDED,
          "failed" => Capabilities::History::FAILED, "canceled" => Capabilities::History::CANCELLED, "none" => Capabilities::History::FAILED
        }.freeze
        # A timeline record's state, and its result once completed (TimelineRecordState, TaskResult).
        RECORD_STATUSES = {
          "pending" => Capabilities::History::QUEUED, "inprogress" => Capabilities::History::RUNNING,
          "succeeded" => Capabilities::History::SUCCEEDED, "succeededwithissues" => Capabilities::History::SUCCEEDED,
          "failed" => Capabilities::History::FAILED, "canceled" => Capabilities::History::CANCELLED,
          "skipped" => Capabilities::History::CANCELLED, "abandoned" => Capabilities::History::CANCELLED
        }.freeze
        WRITE_NEEDS = "Running, retrying or canceling a pipeline run needs a token with Build (Read & execute) from someone who may " \
                      "queue and stop builds of the pipeline, and answering an approval also Pipeline Resources (Use) from one of its approvers".freeze
        FOLLOW = "ci_runs with its id as run, or ci_status, follows it".freeze

        # What a CI tool reads: the project, the filter of its runs, what it is called, its page and default branch.
        Target = Data.define(:project, :query, :what, :page, :branch, :repository_id, :definition_id)

        def self.included(pack)
          repo = pack::REPO_PARAM
          target = { "repo" => repo.merge("description" => "#{repo['description']}. Or name a pipeline instead (optional)"),
                     "pipeline" => PIPELINE_PARAM.merge("description" => "#{PIPELINE_PARAM['description']}. Or name a repository instead (optional)") }
          pack.tool :pipelines,
                    summary: "Lists a repository's or pipeline's runs with their outcome, branch and commit.",
                    description: "The runs of a repository's pipelines or of one pipeline, newest first, with their outcome, branch, commit, " \
                                 "why they started and their page",
                    params_schema: CodeHost::Code.object_schema({
                      **target,
                      "ref" => { "type" => "string", "description" => "Only runs for this branch (optional)" },
                      "result" => { "type" => "string", "enum" => RESULTS, "description" => "Only finished runs with this result, such as failed (optional)" },
                      "since" => { "type" => "string", "description" => "Only runs queued at or after this time, as ISO 8601 (optional)" },
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{RUN_LIMIT}, at most #{MAX_RUNS})" }
                    }, []),
                    read_only: true

          pack.tool :ci_runs,
                    summary: "Lists recent pipeline runs with how long each took compared with the usual time.",
                    description: "A repository's or pipeline's runs, newest first, each with its outcome, when it started and finished and " \
                                 "how long it took, and how long finished runs usually take",
                    params_schema: CodeHost::Code.object_schema({
                      **target,
                      "name" => { "type" => "string", "description" => "Only runs of pipelines whose name contains this, such as release (optional)" },
                      "ref" => { "type" => "string", "description" => "Only runs for this branch (optional)" },
                      "run" => { "type" => "string", "description" => "Only this run, by its id, with each job and how it ended (optional)" },
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{HISTORY_LIMIT}, at most #{MAX_HISTORY})" }
                    }, []),
                    read_only: true

          pack.tool :pipeline_jobs,
                    summary: "Shows a pipeline run's stages and jobs, with why any failed.",
                    description: "The stages and jobs of one run, with each one's outcome, the errors it reported and how long it took. Use " \
                                 "job_log for a job's output",
                    params_schema: CodeHost::Code.object_schema({
                      "project" => PROJECT_PARAM, "build_id" => BUILD_PARAM,
                      "failed_only" => { "type" => "boolean", "description" => "Only the jobs that failed (optional)" }
                    }, %w[project build_id]),
                    read_only: true

          pack.tool :job_log,
                    summary: "Shows the end of a pipeline job's log, where it says why the job failed.",
                    description: "The end of a job's log, where it says why it failed, filtered by text if asked. With a run, its failed " \
                                 "step's log, or the log named by log_id. Without one, the newest failed run of a repository or pipeline, " \
                                 "on a branch when one is named, in the time asked when one is given",
                    params_schema: CodeHost::Code.object_schema({
                      **target,
                      "project" => PROJECT_PARAM.merge("description" => "The project, when a run is named by build_id without a repository or pipeline (optional)"),
                      "build_id" => BUILD_PARAM.merge("description" => "#{BUILD_PARAM['description']} (optional)"),
                      "log_id" => { "type" => "integer", "description" => "One log of the run, as pipeline_jobs shows it (optional)" },
                      "ref" => { "type" => "string", "description" => "Only a run on this branch, when no run is named (optional)" },
                      **CodeHost::LOG_FILTER, **CodeHost::LOG_RANGE
                    }, []),
                    read_only: true

          pack.tool :ci_status,
                    summary: "Shows how CI stands on a branch, its failed jobs and recent deployments.",
                    description: "How a repository's or pipeline's CI stands now: the latest run on a branch (the default branch unless named) " \
                                 "with its failed jobs, how the last runs went and since when it fails, approvals waiting, and what each " \
                                 "environment of the project last received",
                    params_schema: CodeHost::Code.object_schema({
                      **target, "ref" => { "type" => "string", "description" => "The branch (optional, the default branch)" }
                    }, []),
                    read_only: true

          pack.tool :pending_approvals,
                    summary: "Lists the approvals pipeline runs are waiting on in a project.",
                    description: "The approvals and checks a project's pipeline runs are waiting on, each with its id, instructions, who may " \
                                 "approve and how many must. Answer one with approve_check",
                    params_schema: CodeHost::Code.object_schema({ "project" => PROJECT_PARAM }, %w[project]),
                    read_only: true

          pack.tool :run_pipeline,
                    summary: "Runs a pipeline on a branch or tag.",
                    description: "Run a pipeline on a branch or tag, with variables or template parameters if asked",
                    params_schema: CodeHost::Code.object_schema({
                      "pipeline" => PIPELINE_PARAM,
                      "ref" => { "type" => "string", "description" => "The branch or tag, such as main or refs/tags/v1.2 (optional, the pipeline's default branch)" },
                      "variables" => { "type" => "object", "additionalProperties" => { "type" => "string" },
                                       "description" => "Variables by name that the pipeline lets a run set, never a secret, since they are shown and kept (optional)" },
                      "template_parameters" => { "type" => "object", "description" => "A YAML pipeline's parameters by name (optional, their defaults)" }
                    }, %w[pipeline]),
                    read_only: false

          pack.tool :retry_pipeline,
                    summary: "Reruns a pipeline run's failed jobs.",
                    description: "Rerun the failed jobs of a finished run, on the same commit. For a failure that is not the code, such as " \
                                 "a flaky test or an agent that went away",
                    params_schema: CodeHost::Code.object_schema({ "project" => PROJECT_PARAM, "build_id" => BUILD_PARAM }, %w[project build_id]),
                    read_only: false

          pack.tool :cancel_pipeline,
                    summary: "Cancels a pipeline run that has not finished.",
                    description: "Cancel a run that has not finished, such as a deployment that should not go out",
                    params_schema: CodeHost::Code.object_schema({ "project" => PROJECT_PARAM, "build_id" => BUILD_PARAM }, %w[project build_id]),
                    read_only: false

          pack.tool :approve_check,
                    summary: "Approves or rejects an approval a pipeline run waits on.",
                    description: "Approve or reject an approval a pipeline run is waiting on, as pending_approvals lists it, with a comment",
                    params_schema: CodeHost::Code.object_schema({
                      "project" => PROJECT_PARAM,
                      "approval_id" => { "type" => "string", "description" => "The approval's id, as pending_approvals shows it" },
                      "decision" => { "type" => "string", "enum" => DECISIONS.keys, "description" => "approve or reject" },
                      "comment" => { "type" => "string", "description" => "Why, kept on the approval (optional)" }
                    }, %w[project approval_id decision]),
                    read_only: false
        end

        def pipelines(environment_row:, arguments:)
          azure = api(environment_row)
          target = ci_target(azure, arguments)
          limit = whole_number_argument(arguments, "limit", RUN_LIMIT, MAX_RUNS)
          result = arguments["result"].presence
          fail! "result must be one of #{RESULTS.join(', ')}" if result && RESULTS.exclude?(result)

          query = target.query.merge("$top" => limit, "queryOrder" => "queueTimeDescending", "branchName" => branch_ref(ref_argument(arguments)),
                                     "resultFilter" => result, "minTime" => since_argument(arguments)&.iso8601)
          runs = builds(azure, target.project, query)
          return Telemetry.result("No runs of #{target.what} match.", link: link(target.page)) if runs.empty?

          Telemetry.result(runs.map { |build| run_line(build) }.join("\n"), link: link(target.page))
        end

        def ci_runs(environment_row:, arguments:)
          azure = api(environment_row)
          target = ci_target(azure, arguments)
          return one_run(azure, target, positive_id(arguments, "run")) if arguments["run"].present?

          limit = whole_number_argument(arguments, "limit", HISTORY_LIMIT, MAX_HISTORY)
          name = arguments["name"].to_s.strip.presence
          query = target.query.merge("$top" => name ? MAX_RUNS : limit, "queryOrder" => "queueTimeDescending", "branchName" => branch_ref(ref_argument(arguments)))
          runs = builds(azure, target.project, query).map { |build| history_run(build) }
          Capabilities::History.result(runs, what: target.what, link: link(target.page), name: name, limit: limit)
        end

        def pipeline_jobs(environment_row:, arguments:)
          azure = api(environment_row)
          project = project_argument(arguments)
          id = positive_id(arguments, "build_id")
          build = build_of(azure, project, id)
          records = timeline(azure, project, id)
          jobs = records.values.select { |record| record["type"] == JOB }.sort_by { |record| [ record["startTime"].to_s, record["order"].to_i ] }
          jobs = jobs.select { |record| failed_record?(record) } if ActiveModel::Type::Boolean.new.cast(arguments["failed_only"])
          page = link(build.dig("_links", "web", "href"))
          heading = "Run #{build['buildNumber']} (#{id}) of #{build.dig('definition', 'name')} in #{project}, #{run_word(build)}"
          return Telemetry.result("#{heading}, has no#{' failed' if ActiveModel::Type::Boolean.new.cast(arguments['failed_only'])} jobs.", link: page) if jobs.empty?

          Telemetry.result("#{heading}, #{jobs.size} jobs:\n#{jobs.map { |job| job_line(records, job) }.join("\n")}", link: page)
        end

        def job_log(environment_row:, arguments:)
          azure = api(environment_row)
          project, build = if arguments["build_id"].present?
            named = arguments["project"].present? ? project_argument(arguments) : ci_target(azure, arguments).project
            [ named, build_of(azure, named, positive_id(arguments, "build_id")) ]
          else
            target = ci_target(azure, arguments)
            [ target.project, newest_failed_run(azure, target, arguments) ]
          end
          return no_failed_run(arguments) unless build

          records = timeline(azure, project, build["id"])
          record, log_id = log_of(records, arguments)
          heading = "Run #{build['buildNumber']} (#{build['id']}) of #{build.dig('definition', 'name')} in #{project}, #{run_word(build)}, on " \
                    "#{branch_name(build['sourceBranch'])} at #{build['sourceVersion'].to_s[0, 12]}, finished #{build['finishTime'] || 'not yet'}." \
                    "#{" Step: #{step_name(records, record)}." if record}"
          page = link(build.dig("_links", "web", "href"))
          return Telemetry.result("#{heading}\nAzure DevOps keeps no log for this run yet.", link: page) unless log_id

          raw = begin
            azure.text("#{AzureDevopsApi.project(project)}/_apis/build/builds/#{build['id']}/logs/#{log_id}")
          rescue AzureDevopsApi::NotFound
            ""
          end
          return Telemetry.result("#{heading}\nAzure DevOps keeps no log #{log_id} for this run.", link: page) if raw.blank?

          kept, matched = build_log_lines(raw, arguments)
          Telemetry.result(log_text(heading, kept, matched), link: page)
        end

        def ci_status(environment_row:, arguments:)
          azure = api(environment_row)
          target = ci_target(azure, arguments)
          ref = ref_argument(arguments) || target.branch
          fail! "#{target.what} has no default branch, so name a branch with ref." if ref.blank?

          recent = builds(azure, target.project, target.query.merge("$top" => STREAK, "queryOrder" => "queueTimeDescending", "branchName" => branch_ref(ref)))
          latest = recent.first
          sections = [ latest_text(azure, target, ref, latest), streak_text(recent), approvals_text(azure, target.project),
                       environments_text(azure, target.project) ].compact
          Telemetry.result(sections.join("\n\n"), link: link(latest&.dig("_links", "web", "href") || target.page))
        end

        def pending_approvals(environment_row:, arguments:)
          azure = api(environment_row)
          project = project_argument(arguments)
          approvals = pending(azure, project)
          page = link(project_page(azure, project))
          return Telemetry.result("No approval is waiting in #{project}.", link: page) if approvals.empty?

          Telemetry.result("#{approvals.size} approvals waiting in #{project}:\n#{approvals.map { |approval| approval_line(approval) }.join("\n")}", link: page)
        end

        def run_pipeline(environment_row:, arguments:)
          azure = api(environment_row)
          target = ci_target(azure, arguments.slice("pipeline"))
          fail! "Name the pipeline to run as project/pipeline." unless target.definition_id

          definition = azure.get("#{AzureDevopsApi.project(target.project)}/_apis/build/definitions/#{target.definition_id}")
          ref = arguments["ref"].to_s.strip.presence
          fail! "ref must be a branch or tag, such as main or refs/tags/v1.2" if ref && (!ref.match?(CodeHost::REF_FORMAT) || ref.include?(".."))

          variables = hash_argument(arguments, "variables")
          parameters = hash_argument(arguments, "template_parameters")
          started = changing("run #{target.what}") do
            if definition.dig("process", "type").to_i == YAML_PROCESS
              body = { "resources" => ({ "repositories" => { "self" => { "refName" => full_ref(ref) } } } if ref),
                       "variables" => variables.transform_values { |value| { "value" => value.to_s } }.presence, "templateParameters" => parameters.presence }.compact
              run = azure.post("#{AzureDevopsApi.project(target.project)}/_apis/pipelines/#{target.definition_id}/runs", body)
              build_of(azure, target.project, run["id"])
            else
              fail! "#{target.what} is a classic pipeline, which takes no template parameters." if parameters.any?

              body = { "definition" => { "id" => target.definition_id }, "sourceBranch" => (full_ref(ref) if ref),
                       "parameters" => (variables.transform_values(&:to_s).to_json if variables.any?) }.compact
              azure.post("#{AzureDevopsApi.project(target.project)}/_apis/build/builds", body)
            end
          end
          given = variables.any? ? " with #{variables.keys.to_sentence}" : ""
          Telemetry.result("Started run #{started['buildNumber']} (#{started['id']}) of #{target.what} on #{branch_name(started['sourceBranch']) || ref || 'its default branch'}" \
                           "#{given}. It is #{run_word(started)}. #{FOLLOW}.", link: link(started.dig("_links", "web", "href") || target.page))
        end

        def retry_pipeline(environment_row:, arguments:)
          azure = api(environment_row)
          project = project_argument(arguments)
          id = positive_id(arguments, "build_id")
          build = build_of(azure, project, id)
          fail! "Run #{id} in #{project} has not finished, so there is nothing to rerun yet." unless build["status"] == COMPLETED
          fail! "Run #{id} in #{project} succeeded, so it has no failed jobs to rerun. run_pipeline runs it again." if build["result"] == SUCCEEDED

          retried = changing("rerun the failed jobs of run #{id} in #{project}") do
            azure.patch("#{AzureDevopsApi.project(project)}/_apis/build/builds/#{id}", {}, "retry" => true)
          end
          Telemetry.result("Rerunning the failed jobs of run #{build['buildNumber']} (#{id}) of #{build.dig('definition', 'name')} in #{project}, on " \
                           "#{branch_name(build['sourceBranch'])} at #{build['sourceVersion'].to_s[0, 12]}. It is #{run_word(retried.presence || build)}. #{FOLLOW}.",
                           link: link(build.dig("_links", "web", "href")))
        end

        # A run is canceled by setting its status to cancelling (BuildStatus), as Azure DevOps' own Cancel does.
        def cancel_pipeline(environment_row:, arguments:)
          azure = api(environment_row)
          project = project_argument(arguments)
          id = positive_id(arguments, "build_id")
          build = build_of(azure, project, id)
          fail! "Run #{id} in #{project} already finished, #{build['result']}, so there is nothing to cancel." if build["status"] == COMPLETED

          changing("cancel run #{id} in #{project}") { azure.patch("#{AzureDevopsApi.project(project)}/_apis/build/builds/#{id}", { "status" => "cancelling" }) }
          Telemetry.result("Canceling run #{build['buildNumber']} (#{id}) of #{build.dig('definition', 'name')} in #{project}, on " \
                           "#{branch_name(build['sourceBranch'])} at #{build['sourceVersion'].to_s[0, 12]}. #{FOLLOW}.", link: link(build.dig("_links", "web", "href")))
        end

        def approve_check(environment_row:, arguments:)
          azure = api(environment_row)
          project = project_argument(arguments)
          id = arguments["approval_id"].to_s.strip
          fail! "approval_id must be an approval's id, as pending_approvals shows it" unless id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

          status = DECISIONS[arguments["decision"].to_s] || fail!("decision must be approve or reject")
          approval = azure.values(azure.get("#{AzureDevopsApi.project(project)}/_apis/pipelines/approvals", "approvalIds" => id, "$expand" => "steps")).first
          fail! "#{project} has no approval #{id}." unless approval
          fail! "Approval #{id} is #{approval['status']}, so it is no longer waiting." unless approval["status"] == PENDING

          answered = changing("answer approval #{id} in #{project}") do
            azure.patch("#{AzureDevopsApi.project(project)}/_apis/pipelines/approvals", [ { "approvalId" => id, "status" => status, "comment" => arguments["comment"].to_s.presence }.compact ])
          end
          now = azure.values(answered).first.to_h["status"] || status
          Telemetry.result("Answered approval #{id} in #{project}: #{status}. It is now #{now}. ci_status shows the run going on.",
                           link: link(project_page(azure, project)))
        end

        # Whoever the run was queued for, matched to a member by the address Azure DevOps names them by.
        def owner_of(tool_name, environment_row:, arguments:)
          return super unless tool_name == "cancel_pipeline"

          project = project_argument(arguments)
          build = build_of(api(environment_row), project, positive_id(arguments, "build_id"))
          person = build["requestedFor"].to_h
          return if person["displayName"].blank?

          email = person["uniqueName"].to_s
          Owner.new(name: person["displayName"], email: (email if email.match?(URI::MailTo::EMAIL_REGEXP)), role: Owner::ROLE_STARTED,
                    what: "run #{build['buildNumber']} of #{build.dig('definition', 'name')} in #{project}")
        end

        private

        # The repository or pipeline a CI tool reads. A repository's runs are the builds of Azure Repos' repository by its
        # id (Builds - List, repositoryId and repositoryType), a pipeline's the builds of its definition.
        def ci_target(azure, arguments)
          if arguments["repo"].present?
            repo = repo_argument(arguments)
            project, name = project_and_name(repo)
            repository = azure.get(AzureDevopsApi.repository(project, name))
            return Target.new(project: project, query: { "repositoryId" => repository["id"], "repositoryType" => AZURE_REPOS }, what: repo,
                              page: repository["webUrl"], branch: branch_name(repository["defaultBranch"]), repository_id: repository["id"], definition_id: nil)
          end

          pipeline = arguments["pipeline"].to_s.strip
          fail! "Name a repository as project/repository or a pipeline as project/pipeline." unless pipeline.match?(REPO_FORMAT)

          project, named = project_and_name(pipeline)
          definition = definition_named(azure, project, named)
          Target.new(project: project, query: { "definitions" => definition["id"] }, what: "#{project}/#{definition['name']}",
                     page: definition.dig("_links", "web", "href"), branch: branch_name(definition.dig("repository", "defaultBranch")),
                     repository_id: definition.dig("repository", "id"), definition_id: definition["id"])
        rescue AzureDevopsApi::NotFound
          fail! "#{arguments['repo'].presence || arguments['pipeline']} is no repository or pipeline this token can see."
        end

        # A pipeline by its id, or by a name only one pipeline in the project has (Definitions - List, name).
        def definition_named(azure, project, named)
          if (id = Integer(named, exception: false))
            return azure.get("#{AzureDevopsApi.project(project)}/_apis/build/definitions/#{id}")
          end

          found = azure.values(azure.get("#{AzureDevopsApi.project(project)}/_apis/build/definitions", "name" => named))
          fail! "#{project} has no pipeline called #{named}." if found.empty?
          fail! "More than one pipeline in #{project} is called #{named}: #{found.map { |each| each['id'] }.join(', ')}. Name it by its id." if found.size > 1

          found.first
        end

        def builds(azure, project, query) = azure.values(azure.get("#{AzureDevopsApi.project(project)}/_apis/build/builds", query.compact))

        def build_of(azure, project, id)
          azure.get("#{AzureDevopsApi.project(project)}/_apis/build/builds/#{id}")
        rescue AzureDevopsApi::NotFound
          fail! "#{project} has no run #{id} this token can see."
        end

        # A run's timeline records by id. A run that has not started yet has none.
        def timeline(azure, project, id)
          Array(azure.get("#{AzureDevopsApi.project(project)}/_apis/build/builds/#{id}/timeline")["records"]).index_by { |record| record["id"] }
        rescue AzureDevopsApi::NotFound
          {}
        end

        def project_argument(arguments)
          project = arguments["project"].to_s.strip
          fail! "project must be the project's name, such as Shop" unless project.match?(/\A#{NAME}\z/) && !project.match?(/\A\.*\z/)

          project
        end

        def positive_id(arguments, key)
          id = Integer(arguments[key].to_s, exception: false)
          fail! "#{key} must be a whole number" unless id&.positive?

          id
        end

        def hash_argument(arguments, key)
          value = arguments[key]
          return {} if value.blank?
          fail! "#{key} must be an object of names and values" unless value.is_a?(Hash)

          value
        end

        def branch_ref(ref) = ref.present? ? full_ref(ref) : nil

        def full_ref(ref) = ref.start_with?("refs/") ? ref : "#{HEADS}#{ref}"

        # A change Azure DevOps refused is said with what it needs, so a person knows which token or role to give.
        def changing(what)
          yield
        rescue AzureDevopsApi::Refused => error
          fail! Sentence.join("Azure DevOps refused to #{what}", error, after: WRITE_NEEDS)
        end

        def run_word(build) = build["status"] == COMPLETED ? build["result"].to_s : build["status"].to_s

        def run_status(build) = Capabilities::History.status(build["status"] == COMPLETED ? build["result"] : build["status"], RUN_STATUSES)

        def record_status(record) = Capabilities::History.status(record["state"].to_s == COMPLETED ? record["result"] : record["state"], RECORD_STATUSES)

        def failed_record?(record) = [ Capabilities::History::FAILED, Capabilities::History::CANCELLED ].include?(record_status(record)) && record["result"] != "skipped"

        def history_run(build)
          Capabilities::History::Run.new(
            id: build["id"].to_s, number: build["buildNumber"].to_s.presence, name: build.dig("definition", "name").presence || "run #{build['id']}",
            status: run_status(build), started_at: Telemetry.parse_time(build["startTime"] || build["queueTime"]),
            finished_at: (Telemetry.parse_time(build["finishTime"]) if build["status"] == COMPLETED), url: build.dig("_links", "web", "href"),
            detail: [ ("partly succeeded" if build["result"] == "partiallySucceeded"),
                      "#{branch_name(build['sourceBranch'])} at #{build['sourceVersion'].to_s[0, 12]}, #{build['reason']}" ].compact.join(", ")
          )
        end

        # One run with its jobs, each with its log read by job_log, so a watch hears the first job that failed while the run
        # still goes. A job skipped because an earlier one failed is not a failure of its own.
        def one_run(azure, target, id)
          build = build_of(azure, target.project, id)
          if target.definition_id && build.dig("definition", "id") != target.definition_id
            fail! "Run #{id} is a run of #{build.dig('definition', 'name')}, not of #{target.what}."
          end
          if target.repository_id && build.dig("repository", "id") != target.repository_id
            fail! "Run #{id} built #{build.dig('repository', 'name')}, not #{target.what}."
          end

          records = timeline(azure, target.project, id)
          jobs = records.values.select { |record| record["type"] == JOB && record["result"] != "skipped" }.sort_by { |record| [ record["startTime"].to_s, record["order"].to_i ] }
          parts = jobs.map { |job| history_part(records, target.project, id, job) }
          Capabilities::History.result([ history_run(build).with(parts: parts) ], what: target.what, link: link(build.dig("_links", "web", "href")))
        end

        def history_part(records, project, build_id, job)
          error = errors_of(records, job).first
          log = job.dig("log", "id")
          Capabilities::History::Part.new(
            id: job["id"].to_s, name: step_name(records, job), status: record_status(job), started_at: Telemetry.parse_time(job["startTime"]),
            finished_at: Telemetry.parse_time(job["finishTime"]), detail: error && Sentence.clean(error),
            log: log && { Capabilities::History::LOG_TOOL => "job_log", Capabilities::History::LOG_ARGUMENTS => { "project" => project, "build_id" => build_id, "log_id" => log } }
          )
        end

        # A record named with the stage it runs in, which its parent phase's parent is.
        def step_name(records, record)
          names = []
          current = record
          while current
            names.unshift(current["name"]) unless current["type"] == "Phase" || current["name"] == "__default"
            current = records[current["parentId"]]
          end
          names.compact.join(" / ")
        end

        # The errors a record and the tasks inside it reported, the first ones first.
        def errors_of(records, record)
          inside = records.values.select { |each| each["parentId"] == record["id"] }.sort_by { |each| each["order"].to_i }
          [ record, *inside ].flat_map { |each| Array(each["issues"]) }.select { |issue| issue["type"] == "error" }.filter_map { |issue| issue["message"].presence }
        end

        def job_line(records, job)
          took = job["startTime"] && job["finishTime"] ? "  #{(Time.iso8601(job['finishTime']) - Time.iso8601(job['startTime'])).round}s" : ""
          error = errors_of(records, job).first
          log = job.dig("log", "id") ? "  log #{job.dig('log', 'id')}" : ""
          "  #{step_name(records, job)}  #{job['state'] == COMPLETED ? job['result'] : job['state']}#{took}#{log}#{"\n    #{Sentence.clean(error)}" if error}"
        rescue ArgumentError
          "  #{step_name(records, job)}  #{job['result'] || job['state']}"
        end

        # The record whose log to read: the one named, else the first failed step, else the last job.
        def log_of(records, arguments)
          if arguments["log_id"].present?
            wanted = positive_id(arguments, "log_id")
            return [ records.values.find { |record| record.dig("log", "id") == wanted }, wanted ]
          end

          failed = records.values.select { |record| record["type"] == TASK && record["result"] == "failed" && record.dig("log", "id") }.min_by { |record| record["finishTime"].to_s }
          chosen = failed || records.values.select { |record| record["type"] == JOB && record.dig("log", "id") }.max_by { |record| record["finishTime"].to_s }
          [ chosen, chosen&.dig("log", "id") ]
        end

        # The newest failed run of the repository or pipeline, on the branch and in the time asked.
        def newest_failed_run(azure, target, arguments)
          started, ended = Telemetry.range(arguments, default_minutes: CodeHost::LOG_RANGE_MINUTES, max_minutes: CodeHost::LOG_RANGE_MINUTES) if ranged?(arguments)
          query = target.query.merge("$top" => FAILED_CANDIDATES, "queryOrder" => "finishTimeDescending", "resultFilter" => "failed",
                                     "branchName" => branch_ref(ref_argument(arguments)))
          builds(azure, target.project, query).find do |build|
            finished = Telemetry.parse_time(build["finishTime"])
            started.nil? || (finished && finished.between?(started, ended))
          end
        end

        def ranged?(arguments) = %w[minutes start end].any? { |key| arguments[key].present? }

        def no_failed_run(arguments)
          where = [ ("on #{arguments['ref']}" if arguments["ref"].present?), ("in that time" if ranged?(arguments)) ].compact.join(" ")
          "No failed run#{" #{where}" if where.present?} among the newest #{FAILED_CANDIDATES} failed runs."
        end

        def run_line(build)
          "#{build['queueTime']}  run #{build['buildNumber']} (#{build['id']})  #{build.dig('definition', 'name')}  #{run_word(build)}  " \
            "#{branch_name(build['sourceBranch'])}  #{build['sourceVersion'].to_s[0, 12]}  #{build['reason']}  #{build.dig('_links', 'web', 'href')}"
        end

        def latest_text(azure, target, ref, latest)
          return "No run on #{ref} of #{target.what}. If its CI runs elsewhere, ask that connection." unless latest

          text = "Latest run on #{ref}: #{latest['buildNumber']} (#{latest['id']}) of #{latest.dig('definition', 'name')}, #{run_word(latest)}, commit " \
                 "#{latest['sourceVersion'].to_s[0, 12]}, started by #{latest['reason']} at #{latest['queueTime']}."
          return text unless run_status(latest) == Capabilities::History::FAILED

          records = timeline(azure, target.project, latest["id"])
          failed = records.values.select { |record| record["type"] == JOB && failed_record?(record) }
          "#{text}\nFailed jobs:\n#{failed.map { |job| job_line(records, job) }.join("\n").presence || '  none listed'}\njob_log with its build_id reads why."
        end

        # When the branch last passed, so a failure that started a while ago reads differently from a new one.
        def streak_text(recent)
          return nil if recent.size < 2

          passed = recent.find { |build| run_status(build) == Capabilities::History::SUCCEEDED }
          since = if run_status(recent.first) == Capabilities::History::FAILED
            passed ? " It last passed in run #{passed['buildNumber']} (#{passed['id']}) at #{passed['queueTime']}." : " None of these passed."
          end
          "The last #{recent.size} runs, newest first: #{recent.map { |build| run_word(build) }.join(', ')}.#{since}"
        end

        # Approvals waiting in the project (Approvals - Query, state pending), which a run waits on before a stage.
        def pending(azure, project)
          azure.values(azure.get("#{AzureDevopsApi.project(project)}/_apis/pipelines/approvals", "state" => PENDING, "$expand" => "steps", "top" => APPROVALS_SHOWN))
        end

        def approvals_text(azure, project)
          waiting = pending(azure, project)
          return nil if waiting.empty?

          "Approvals waiting in #{project}:\n#{waiting.first(5).map { |approval| approval_line(approval) }.join("\n")}"
        rescue AzureDevopsApi::Refused
          nil
        end

        def approval_line(approval)
          approvers = Array(approval["steps"]).filter_map { |step| step.dig("assignedApprover", "displayName") }.uniq
          "  #{approval['id']}  waiting since #{approval['createdOn']}  #{approval['minRequiredApprovers'] || 1} of #{approvers.to_sentence.presence || 'its approvers'} " \
            "must approve#{"  #{Sentence.clean(approval['instructions'])}" if approval['instructions'].present?}"
        end
      end
    end
  end
end
