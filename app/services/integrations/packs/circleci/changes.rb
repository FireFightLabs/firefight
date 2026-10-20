module Integrations
  module Packs
    class Circleci
      # What changes a project's CI: rerunning a workflow and cancelling one (v2 rerunWorkflow and cancelWorkflow),
      # approving a job a workflow holds for a person (v2 approvePendingApprovalJobById, with the approval_request_id v2
      # listWorkflowJobs gives an approval job) and running a pipeline on a branch or tag (v3 POST /runs). Each goes
      # through the gateway as a write, so a member needs a grant and an investigation is never offered one.
      module Changes
        # v2's job statuses a workflow holds an approval job in while it waits for a person (listWorkflowJobs, status).
        ON_HOLD = "on_hold".freeze
        FOLLOW = "get_workflow or ci_runs follows it".freeze
        WRITE_NEEDS = "It needs a token whose user may run and manage the project's pipelines".freeze
        CANCEL_TOOL = "cancel_workflow".freeze

        def self.included(pack)
          workflow = { "type" => "string", "description" => "A workflow's id, as get_run or list_workflows shows it" }

          pack.tool :rerun_workflow,
                    summary: "Reruns a workflow, in full or from the failed jobs.",
                    description: "Rerun a workflow that ended, every job or only the failed ones and those after them, on the same commit. For a " \
                                 "failure that is not the code, such as a flaky test or a machine that went away",
                    params_schema: { "type" => "object", "properties" => {
                      "workflow" => workflow, "from_failed" => { "type" => "boolean", "description" => "Only the failed jobs and the jobs after them (optional)" }
                    }, "required" => %w[workflow] },
                    read_only: false

          pack.tool :cancel_workflow,
                    summary: "Cancels a running workflow.",
                    description: "Cancel a workflow that has not ended, such as a deploy that should not go out",
                    params_schema: { "type" => "object", "properties" => { "workflow" => workflow }, "required" => %w[workflow] },
                    read_only: false

          pack.tool :approve_job,
                    summary: "Approves a job a workflow holds for a person, so it carries on.",
                    description: "Approve a hold in a workflow, the approval job it waits on, so the jobs after it run, such as a deploy to " \
                                 "production. Only when a person asks or a runbook step says to, since it cannot be taken back",
                    params_schema: { "type" => "object", "properties" => {
                      "workflow" => workflow,
                      "job" => { "type" => "string", "description" => "The approval job, by its name or id (optional when the workflow holds one)" }
                    }, "required" => %w[workflow] },
                    read_only: false

          pack.tool :run_pipeline,
                    summary: "Runs a project's pipeline on a branch or tag.",
                    description: "Run a project's pipeline on a branch or tag (the default branch unless named), with pipeline parameters if asked",
                    params_schema: { "type" => "object", "properties" => {
                      "project" => Circleci::PROJECT_PARAM,
                      "branch" => { "type" => "string", "description" => "The branch (optional, the project's default branch)" },
                      "tag" => { "type" => "string", "description" => "A tag instead of a branch (optional)" },
                      "pipeline" => { "type" => "string", "description" => "Which of the project's pipelines, by its name or id, when it has more than one (optional)" },
                      "parameters" => { "type" => "object", "description" => "Pipeline parameters by name, never a secret, since they are shown and kept (optional)" }
                    }, "required" => %w[project] },
                    read_only: false
        end

        def rerun_workflow(environment_row:, arguments:)
          id = id_argument(arguments, "workflow")
          workflow = read_workflow(environment_row, id)
          status = status_of(workflow["attributes"])
          fail! "Workflow #{id} has not ended, so it is not rerun. cancel_workflow stops it." unless Capabilities::History::FINISHED.include?(status)

          from_failed = ActiveModel::Type::Boolean.new.cast(arguments["from_failed"]) == true
          fail! "Workflow #{id} passed, so it has no failed jobs to rerun. Rerun it in full instead." if from_failed && status == Capabilities::History::SUCCEEDED

          rerun = changing("rerun workflow #{id}") { api(environment_row).rerun(id, from_failed: from_failed) }
          what = from_failed ? "its failed jobs and those after them" : "every job"
          Telemetry.result("Rerunning workflow #{workflow.dig('attributes', 'name')} (#{id}), #{what}. The rerun is workflow #{rerun['workflow_id']}. #{FOLLOW}.",
                           link: workflow_link(environment_row, { "id" => rerun["workflow_id"].presence || id }))
        end

        def cancel_workflow(environment_row:, arguments:)
          id = id_argument(arguments, "workflow")
          workflow = read_workflow(environment_row, id)
          if Capabilities::History::FINISHED.include?(status_of(workflow["attributes"]))
            fail! "Workflow #{id} already ended, #{state_words(workflow['attributes'])}, so there is nothing to cancel."
          end

          changing("cancel workflow #{id}") { api(environment_row).cancel(id) }
          Telemetry.result("Cancelling workflow #{workflow.dig('attributes', 'name')} (#{id}). CircleCI cancels it a moment later. #{FOLLOW}.",
                           link: workflow_link(environment_row, workflow))
        end

        def approve_job(environment_row:, arguments:)
          id = id_argument(arguments, "workflow")
          held = api(environment_row).workflow_jobs(id).select { |job| job["type"] == Runs::APPROVAL && job["status"] == ON_HOLD }
          fail! "Workflow #{id} holds no job for approval now." if held.empty?

          asked = arguments["job"].to_s.strip
          job = if asked.present? then held.find { |each| each["id"] == asked || each["name"].to_s.casecmp?(asked) }
          elsif held.one? then held.first
          end
          fail! "Workflow #{id} holds #{held.map { |each| each['name'] }.to_sentence} for approval. Name the job." unless job

          changing("approve #{job['name']} in workflow #{id}") { api(environment_row).approve(id, job["approval_request_id"].presence || job["id"]) }
          Telemetry.result("Approved #{job['name']} in workflow #{id}, so the jobs after it run now. An approval cannot be taken back, and " \
                           "cancel_workflow stops what follows. #{FOLLOW}.", link: workflow_link(environment_row, { "id" => id }))
        end

        def run_pipeline(environment_row:, arguments:)
          project = find_project(environment_row, arguments)
          definition = pipeline_definition(environment_row, project, arguments["pipeline"].to_s.strip)
          branch = arguments["branch"].to_s.strip.presence
          tag = arguments["tag"].to_s.strip.presence
          fail! "Name a branch or a tag, not both." if branch && tag

          branch ||= project.branch unless tag
          fail! "#{project.label} has no default branch Firefight knows, so name a branch or tag." unless branch || tag

          where = tag ? { "tag" => tag } : { "branch" => branch }
          parameters = arguments["parameters"].presence || {}
          fail! "parameters must be an object of names and values" unless parameters.is_a?(Hash)

          started = changing("run #{project.label}'s pipeline") do
            api(environment_row).start_run(definition["id"], project.id, checkout: where, config: where, parameters: parameters)
          end
          given = parameters.any? ? " with #{parameters.keys.to_sentence}" : ""
          Telemetry.result("Started a run of #{definition.dig('attributes', 'name') || 'the pipeline'} on #{tag ? "tag #{tag}" : branch} in #{project.label}#{given}. " \
                           "It is run #{started.dig('data', 'id')}. ci_runs with that run follows it.", link: project_link(environment_row, project))
        end

        # Whoever started the workflow, by the name CircleCI keeps for them (v2 getWorkflowById started_by, then getUser).
        def owner_of(tool_name, environment_row:, arguments:)
          return super unless tool_name == CANCEL_TOOL

          workflow = api(environment_row).workflow_summary(id_argument(arguments, "workflow"))
          return if workflow["started_by"].blank?

          user = api(environment_row).user(workflow["started_by"])
          name = user["name"].presence || user["login"].presence
          name && Owner.new(name: name, role: Owner::ROLE_STARTED, what: "workflow #{workflow['name']} of #{workflow['project_slug']}")
        rescue CircleciApi::Error
          nil
        end

        private

        # A change CircleCI refused is said with what it needs.
        def changing(what)
          yield
        rescue CircleciApi::Refused => error
          fail! Sentence.join("CircleCI refused to #{what}", error, after: WRITE_NEEDS)
        end

        # The project's pipeline, by name or id, or its only one (v3 GET /pipelines and /pipelines/:id).
        def pipeline_definition(environment_row, project, asked)
          definitions = api(environment_row).pipelines(project.id).map { |listed| api(environment_row).pipeline(listed["id"], project.id)["data"].to_h }
          fail! "#{project.label} has no pipeline to run." if definitions.empty?
          return definitions.first if asked.blank? && definitions.one?

          found = asked.present? && definitions.find { |each| each["id"] == asked || each.dig("attributes", "name").to_s.casecmp?(asked) }
          found || fail!("#{project.label} has the pipelines #{definitions.map { |each| each.dig('attributes', 'name') }.compact.to_sentence}. Name one with pipeline.")
        end
      end
    end
  end
end
