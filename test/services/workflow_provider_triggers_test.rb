require "test_helper"

class WorkflowProviderTriggersTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    @github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    @row = @github.integration_environments.create!
  end

  def look(query) = { "id" => "look", "name" => "look", "kind" => "call_tool", "config" => { "tool" => Mcp::Tools::SEARCH_INCIDENTS, "arguments" => { "query" => query } } }

  def published(name, trigger, query: "{{trigger}}")
    workflow = Workflow.create!(workspace: @workspace, name: name, created_by: @alice)
    draft = workflow.open_draft!(by: @alice)
    draft.update!(trigger: { "inputs" => [] }.merge(trigger), steps: [ look(query) ], edges: [])
    assert_empty draft.problems
    result = WorkflowPublishService.new(workflow).publish!(draft.reload, by: @alice)
    assert result.ok, result.words
    workflow.reload
  end

  def condition(field, *values) = { "field" => field, "operator" => PolicyRule::OPERATOR_IS_ONE_OF, "value" => values }

  def workflow_run(conclusion: "failure", attempt: 1)
    { "action" => "completed", "repository" => { "full_name" => "acme/web" },
      "workflow_run" => { "id" => 7, "run_attempt" => attempt, "name" => "CI", "conclusion" => conclusion, "head_branch" => "main",
                          "head_sha" => "abc123", "html_url" => "https://github.com/acme/web/actions/runs/7" } }
  end

  test "a CI run that failed starts a workflow waiting for one, once per attempt however often it is delivered" do
    workflow = published("CI broke", { "kind" => Workflow::Trigger::KIND_DEPLOY_FINISHED,
                                       "conditions" => [ condition("outcome", "failed"), condition("kind", "ci") ] }, query: "{{trigger.run.place}}")
    headers = { "x-github-event" => "workflow_run" }

    perform_enqueued_jobs(only: WorkflowEventJob) do
      2.times { Integrations::MapEvents.report_runs_ended!([ @row ], workflow_run, headers: headers) }
      Integrations::MapEvents.report_runs_ended!([ @row ], workflow_run(conclusion: "success", attempt: 2), headers: headers)
    end

    run = workflow.runs.sole
    assert_equal({ "kind" => "ci", "outcome" => "failed", "provider" => "GitHub", "reference" => "run:7:1", "name" => "CI", "place" => "acme/web",
                   "ref" => "main", "commit" => "abc123", "url" => "https://github.com/acme/web/actions/runs/7", "environment" => nil, "connection" => "GitHub" },
                 run.trigger_payload["run"])
  end

  test "each code host and deploy platform says which runs ended and how" do
    github = Integrations::MapEventSources::Github
    deploy = { "deployment_status" => { "id" => 3, "state" => "error", "environment" => "production", "target_url" => "https://x" },
               "deployment" => { "ref" => "main", "sha" => "def" }, "repository" => { "full_name" => "acme/web" } }
    assert_equal [ [ "deploy", "failed", "production" ] ], github.runs_ended(deploy, headers: { "x-github-event" => "deployment_status" }).map { |run| [ run.kind, run.outcome, run.environment ] }
    assert_empty github.runs_ended(deploy.deep_merge("deployment_status" => { "state" => "in_progress" }), headers: { "x-github-event" => "deployment_status" })
    assert_empty github.runs_ended(workflow_run(conclusion: "skipped"), headers: { "x-github-event" => "workflow_run" })

    gitlab = Integrations::MapEventSources::Gitlab
    pipeline = { "project" => { "path_with_namespace" => "acme/api" }, "object_attributes" => { "id" => 9, "status" => "canceled", "ref" => "main", "sha" => "f00" } }
    assert_equal [ [ "ci", "cancelled" ] ], gitlab.runs_ended(pipeline, headers: { "x-gitlab-event" => "Pipeline Hook" }).map { |run| [ run.kind, run.outcome ] }
    assert_empty gitlab.runs_ended(pipeline.deep_merge("object_attributes" => { "status" => "running" }), headers: { "x-gitlab-event" => "Pipeline Hook" })
    deployment = { "project" => { "path_with_namespace" => "acme/api" }, "status" => "success", "deployment_id" => 4, "environment" => "staging" }
    assert_equal [ [ "deploy", "succeeded" ] ], gitlab.runs_ended(deployment, headers: { "x-gitlab-event" => "Deployment Hook" }).map { |run| [ run.kind, run.outcome ] }

    bitbucket = Integrations::MapEventSources::Bitbucket
    status = { "repository" => { "full_name" => "acme/app" }, "commit_status" => { "state" => "FAILED", "key" => "build", "commit" => { "hash" => "c1" } } }
    assert_equal [ [ "ci", "failed" ] ], bitbucket.runs_ended(status, headers: { "x-event-key" => "repo:commit_status_updated" }).map { |run| [ run.kind, run.outcome ] }
    assert_empty bitbucket.runs_ended(status.deep_merge("commit_status" => { "state" => "INPROGRESS" }), headers: { "x-event-key" => "repo:commit_status_updated" })

    netlify = Integrations::MapEventSources::Netlify
    published_deploy = { "id" => "d1", "site_id" => "s1", "name" => "docs", "context" => "deploy-preview" }
    assert_equal [ [ "deploy", "succeeded", "deploy-preview" ] ], netlify.runs_ended(published_deploy, headers: { "x-netlify-event" => "deploy_created" }).map { |run| [ run.kind, run.outcome, run.environment ] }
    assert_empty netlify.runs_ended(published_deploy, headers: { "x-netlify-event" => "deploy_building" })
  end

  test "a change the map records starts a workflow waiting for that kind of change" do
    workflow = published("Gone", { "kind" => Workflow::Trigger::KIND_RESOURCE_CHANGED, "conditions" => [ condition("change", ResourceMap::Change::KIND_REMOVED) ] },
                         query: "{{trigger.resource.name}}")
    resource = ResourceMap::Resource.create!(workspace: @workspace, provider: "github", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/web",
                                             name: "acme/web", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)

    perform_enqueued_jobs(only: WorkflowEventJob) do
      resource.changes_seen.create!(workspace: @workspace, kind: ResourceMap::Change::KIND_RENAMED, from_value: "web", to_value: "acme/web", happened_at: Time.current)
      resource.changes_seen.create!(workspace: @workspace, kind: ResourceMap::Change::KIND_REMOVED, happened_at: Time.current)
    end

    run = workflow.runs.sole
    assert_equal "removed", run.trigger_payload.dig("change", "kind")
    assert_equal "acme/web is gone", run.trigger_payload.dig("change", "words")
  end

  test "a leaked secret starts a workflow and still reaches the security module" do
    workflow = published("Leak", { "kind" => Workflow::Trigger::KIND_SECURITY_EVENT, "conditions" => [ condition("public", "true") ] })
    Investigation::SecurityTrigger.any_instance.expects(:receive!)
    event = Integrations::SecurityEvents::Event.new(kind: Integrations::SecurityEvents::KIND_LEAKED_SECRET, provider: "GitHub", reference: "acme/web#1",
                                                    place: "acme/web", what: "AWS key", url: "https://github.com/acme/web/security/1", public: true)

    perform_enqueued_jobs(only: WorkflowEventJob) { SecurityEventJob.perform_now(@workspace.id, event.to_h.stringify_keys) }

    assert_equal "AWS key", workflow.runs.sole.trigger_payload.dig("event", "what")
  end

  test "an issue handed to Firefight starts a workflow beside Halon taking it up" do
    workflow = published("Triage", { "kind" => Workflow::Trigger::KIND_ISSUE_ASSIGNED }, query: "{{trigger.issue.title}}")
    Conversation::IssueSessions.any_instance.stubs(:asked)
    event = Integrations::AgentSessions::Event.new(kind: Integrations::AgentSessions::STARTED, session_id: "s-1", text: "Look at this", context: nil,
                                                   issue_key: "ENG-12", issue_title: "Checkout slow", issue_url: "https://linear.app/x/ENG-12",
                                                   asker_email: "alice@example.com", asker_name: "Alice Smith")

    perform_enqueued_jobs(only: WorkflowEventJob) { Conversation::IssueSessions.receive!(@row, event) }

    issue = workflow.runs.sole.trigger_payload["issue"]
    assert_equal [ "ENG-12", "Checkout slow", "alice@example.com" ], issue.values_at("key", "title", "asked_by_email")
  end

  test "every kind of trigger can now be published" do
    assert_equal Workflow::Trigger::KINDS.sort, Workflow::Trigger::PUBLISHABLE.sort
  end
end
