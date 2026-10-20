module Integrations
  # Calls to CircleCI's API with a person's own API token. v2 is described in circleci.com/api/v2/openapi.json and v3 in
  # circleci.com/docs/api/v3 (index.md and a page per entity), and each path here is as its reference writes it. v3
  # holds a project's runs, their workflows and jobs, and a job's steps and output, by id. v2 holds what v3 does not yet:
  # approving a held job, rerunning and cancelling a workflow, deploys and rollbacks, outbound webhooks, and the project
  # slug and default branch. v2 takes the token in Circle-Token and v3 as a bearer token (v3 conventions.md, Auth).
  class CircleciApi
    class Error < Integrations::Error; end
    class NotFound < Error
      include Integrations::NotFound
    end
    # The token is not accepted, may not do this, or CircleCI turned the request down as it stands, such as a webhook past
    # a project's 25 or a rollback with no rollback pipeline.
    class Refused < Error; end
    REFINED = { 400 => Refused, 401 => Refused, 403 => Refused, 404 => NotFound, 409 => Refused }.freeze
    REFINE = ->(code, _reason) { REFINED[code] }

    ROOT = "https://circleci.com/api".freeze
    V2 = "/v2".freeze
    V3 = "/v3".freeze
    PROVIDER = "CircleCI".freeze
    TOKEN_HEADER = "Circle-Token".freeze
    # v3 bounds a page per operation and refuses one past it (runs and workflows at 20, projects at 50).
    RUN_PAGE = 20
    PROJECT_PAGE = 50
    DEPLOY_PAGE = 100
    MAX_PAGES = 10
    # A step's output can be long, and its end usually says why it failed.
    TEXT_LIMIT = 2_000_000

    def initialize(token)
      @token = token
    end

    # The user the token acts as (v2 getCurrentUser).
    def me = get(V2, "/me")

    # The organizations the user belongs to or collaborates in, each with its id, name, vcs-type and slug (v2
    # getCollaborations).
    def collaborations = Array(get(V2, "/me/collaborations"))

    # An organization's projects, by id and name (v3 GET /projects with filter[org_id]).
    def projects(org_id)
      pages(V3, "/projects", { "filter[org_id]" => org_id, "page[limit]" => PROJECT_PAGE })
    end

    def project(id) = get(V3, "/projects/#{Http.segment(id)}")

    # A project by its slug, with its id, organization and repository (v2 getProjectBySlug). The slug's slashes stay.
    def project_by_slug(slug) = get(V2, "/project/#{slug_path(slug)}")

    # A project's runs, one page of at most limit (v3 GET /runs with filter[project_id]).
    def runs(project_id, limit: RUN_PAGE)
      Array(get(V3, "/runs", "filter[project_id]" => project_id, "page[limit]" => limit.clamp(1, RUN_PAGE))["data"])
    end

    def run(id) = get(V3, "/runs/#{Http.segment(id)}")

    # A run's workflows, newest first (v3 GET /workflows with filter[run_id]).
    def workflows(run_id)
      pages(V3, "/workflows", { "filter[run_id]" => run_id, "page[limit]" => RUN_PAGE }).items
    end

    def workflow(id) = get(V3, "/workflows/#{Http.segment(id)}")

    # A workflow as v2 has it, with its project slug, pipeline number and who started it (v2 getWorkflowById).
    def workflow_summary(id) = get(V2, "/workflow/#{Http.segment(id)}")

    # A workflow's jobs, every page (v3 GET /jobs with filter[workflow_id]).
    def jobs(workflow_id) = pages(V3, "/jobs", { "filter[workflow_id]" => workflow_id }).items

    # A workflow's jobs as v2 has them, with each approval job's approval_request_id (v2 listWorkflowJobs).
    def workflow_jobs(workflow_id) = Array(get(V2, "/workflow/#{Http.segment(workflow_id)}/job")["items"])

    # One job with its steps and parallel executions (v3 GET /jobs/:id).
    def job(id) = get(V3, "/jobs/#{Http.segment(id)}")

    # What one step of one parallel execution printed, stdout or stderr (v3 GET /jobs/:id/stdout and /stderr).
    def step_output(job_id, step:, execution:, stream:)
      raise ArgumentError, "stream is stdout or stderr" unless %w[stdout stderr].include?(stream)

      body = call(V3, uri(V3, "/jobs/#{Http.segment(job_id)}/#{stream}", "filter[step_num]" => step, "filter[execution]" => execution), as: :text)
      body.bytesize > TEXT_LIMIT ? body.byteslice(-TEXT_LIMIT, TEXT_LIMIT).scrub : body
    end

    def artifacts(job_id) = Array(get(V3, "/jobs/#{Http.segment(job_id)}/artifacts")["data"])

    # A job's test results, a page of 20 at a time (v3 GET /test-results with filter[job_id]).
    def test_results(job_id, pages: 5)
      pages(V3, "/test-results", { "filter[job_id]" => job_id, "page[limit]" => RUN_PAGE }, max_pages: pages)
    end

    # A project's pipeline definitions by id (v3 GET /pipelines), and one with its name and repository (GET /pipelines/:id,
    # which needs the project for an OAuth project's own pipeline).
    def pipelines(project_id) = Array(get(V3, "/pipelines", "filter[project_id]" => project_id)["data"])

    def pipeline(id, project_id) = get(V3, "/pipelines/#{Http.segment(id)}", "filter[project_id]" => project_id)

    # Fires a run of a pipeline definition on a branch or tag, with its parameters (v3 POST /runs).
    def start_run(pipeline_id, project_id, checkout:, config:, parameters:)
      attributes = { "checkout" => checkout.presence, "config" => config.presence, "parameters" => parameters.presence }.compact
      body = { "data" => { "attributes" => attributes, "references" => { "pipeline" => { "id" => pipeline_id } } } }
      write(V3, Net::HTTP::Post, "/runs", body, "filter[project_id]" => project_id)
    end

    def rerun(workflow_id, from_failed:) = write(V2, Net::HTTP::Post, "/workflow/#{Http.segment(workflow_id)}/rerun", { "from_failed" => from_failed })

    def cancel(workflow_id) = write(V2, Net::HTTP::Post, "/workflow/#{Http.segment(workflow_id)}/cancel")

    def approve(workflow_id, approval_request_id)
      write(V2, Net::HTTP::Post, "/workflow/#{Http.segment(workflow_id)}/approve/#{Http.segment(approval_request_id)}")
    end

    # A user by id, with their login and name (v2 getUser).
    def user(id) = get(V2, "/user/#{Http.segment(id)}")

    # An organization's deploy environments, and a project's deploy components with each one's versions (v2 listEnvironments,
    # listComponents and listComponentVersions).
    def environments(org_id) = pages(V2, "/deploy/environments", { "org-id" => org_id, "page-size" => DEPLOY_PAGE }, token: "page-token").items

    def components(org_id, project_id)
      pages(V2, "/deploy/components", { "org-id" => org_id, "project-id" => project_id, "page-size" => DEPLOY_PAGE }, token: "page-token").items
    end

    def versions(component_id) = pages(V2, "/deploy/components/#{Http.segment(component_id)}/versions", {}, token: "page-token").items

    # Rolls a component back in an environment through the project's rollback pipeline (v2 rollbackProject).
    def rollback(project_id, body) = write(V2, Net::HTTP::Post, "/projects/#{Http.segment(project_id)}/rollback", body)

    # A project's outbound webhooks (v2 getWebhooks), and making, changing and removing one (createWebhook, updateWebhook,
    # deleteWebhook). Only a project can be a webhook's scope.
    def webhooks(project_id) = Array(get(V2, "/webhook", "scope-id" => project_id, "scope-type" => "project")["items"])

    def create_webhook(project_id, name:, url:, secret:, events:)
      body = { "name" => name, "events" => events, "url" => url, "verify-tls" => true, "signing-secret" => secret,
               "scope" => { "id" => project_id, "type" => "project" } }
      write(V2, Net::HTTP::Post, "/webhook", body)
    end

    def update_webhook(id, url:, secret:, events:)
      write(V2, Net::HTTP::Put, "/webhook/#{Http.segment(id)}", { "events" => events, "url" => url, "signing-secret" => secret, "verify-tls" => true, "is-enabled" => true })
    end

    def delete_webhook(id) = write(V2, Net::HTTP::Delete, "/webhook/#{Http.segment(id)}")

    # Any GET of either version, for the general read (Integrations::ApiReads), whose guard checks the path first. The path
    # starts with the version it reads.
    def read(path, query)
      version = path.start_with?("#{V3}/") ? V3 : V2
      get(version, path.delete_prefix(version), query)
    end

    private

    def get(version, path, query = {}) = call(version, uri(version, path, query))

    def write(version, verb, path, body = nil, query = {})
      target = uri(version, path, query)
      request = verb.new(target)
      if body
        request["Content-Type"] = "application/json"
        request.body = body.to_json
      end
      call(version, target, request: request)
    end

    # Every page of a list up to max_pages, by v3's page.next or v2's next_page_token, as a Pages::Read.
    def pages(version, path, query, token: "page[cursor]", max_pages: MAX_PAGES)
      Pages.read(max_pages: max_pages) do |cursor|
        answer = get(version, path, cursor ? query.merge(token => cursor) : query)
        items = version == V3 ? answer["data"] : answer["items"]
        [ Array(items), version == V3 ? answer.dig("page", "next") : answer["next_page_token"] ]
      end
    end

    def uri(version, path, query)
      target = URI.parse("#{ROOT}#{version}#{path}")
      pairs = query.compact
      target.query = URI.encode_www_form(pairs) if pairs.any?
      target
    end

    def slug_path(slug) = slug.to_s.split("/").map { |segment| Http.segment(segment) }.join("/")

    def call(version, target, request: Net::HTTP::Get.new(target), **)
      if version == V3
        request["Authorization"] = "Bearer #{@token}"
      else
        request[TOKEN_HEADER] = @token
      end
      Http.json(target, request, error_class: Error, provider_name: PROVIDER, refine: REFINE, **)
    end
  end
end
