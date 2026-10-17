require "test_helper"

# A connection's tool that changes who can reach something or sets a secret always waits for a person when no person is
# making the call, whatever grants allow and however the call reached the gateway: a workflow's step, a command line
# tool relayed from a run's sandbox, or a runbook someone confirmed on its card.
class AbilityGatewayAccessToolsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    github.integration_environments.create!(credentials: { token: "x" }.to_json)
    @secret = github.tools.create!(name: "set_actions_secret", description: "Set a secret", enabled: true, read_only: false, params_schema: { "type" => "object" })
    workflow = Workflow.create!(workspace: @workspace, name: "Rotate", created_by: @alice)
    version = workflow.open_draft!(by: @alice)
    agent = Agent.create!(workspace: @workspace, name: "Rotate workflow", slug: "rotate_workflow")
    @run = workflow.runs.create!(workspace: @workspace, version: version, agent: agent, status: Workflow::Run::STATUS_RUNNING, trigger_kind: Workflow::Trigger::KIND_MANUAL,
                                 start_key: "run", started_by_kind: Workflow::Run::STARTED_BY_PERSON)
    @step = @run.steps.create!(step_key: "rotate", iteration: "", status: "waiting")
    Ability::Grant.create!(workspace: @workspace, principal: @run.acting_principal, action: Ability::Action.lookup(@secret.action_key, @workspace))
    Integrations::NativeExecutor.stubs(:call).returns({ "content" => [ { "type" => "text", "text" => "Set." } ] })
  end

  test "a workflow step's call to a provider's access tool waits for an admin, whatever its grants" do
    agent_run = Workflow::AgentRun.new(run: @run, record: @step)

    held = assert_raises(AbilityGateway::PendingApproval) { agent_run.tool_call(action_key: @secret.action_key, params: { "name" => "TOKEN" }) { :set } }

    assert_person_asked held.approval
  end

  test "a runbook someone confirmed on its card does not answer for a provider's access tool" do
    @run.update!(confirmed_by: @alice)
    agent_run = Workflow::AgentRun.new(run: @run, record: @step)

    held = assert_raises(AbilityGateway::PendingApproval) { agent_run.tool_call(action_key: @secret.action_key, params: { "name" => "TOKEN" }) { :set } }

    assert_person_asked held.approval
  end

  test "a command line tool relayed from a run's sandbox waits for an admin before an access tool runs" do
    agent_run = Workflow::AgentRun.new(run: @run, record: @step)
    Integrations::NativeExecutor.expects(:call).never

    Chat::Tools::Connection.new(agent_run, @secret).run({ "name" => "TOKEN" }, environment_entry: nil, tool_call_id: nil, relayed: true)

    assert_person_asked agent_run.held
  end

  test "a whole API's tool that writes waits for an admin outside a person's own call, and its reads and Firefight's own capability calls do not" do
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    northflank.integration_environments.create!(credentials: { token: "x" }.to_json)
    api = northflank.tools.create!(name: "api_request", description: "Call the API", enabled: true, read_only: false, params_schema: { "type" => "object" })
    Ability::Grant.create!(workspace: @workspace, principal: @run.acting_principal, action: Ability::Action.lookup(api.action_key, @workspace))
    agent_run = Workflow::AgentRun.new(run: @run, record: @step)
    write = { "method" => "POST", "path" => "/v1/projects/shop/secrets", "body" => {} }

    held = assert_raises(AbilityGateway::PendingApproval) { agent_run.tool_call(action_key: api.action_key, params: write) { :written } }
    assert_person_asked held.approval
    assert_equal :read, agent_run.tool_call(action_key: api.action_key, params: { "method" => "GET", "path" => "/v1/projects" }) { :read }.value
    assert_equal :restarted, agent_run.tool_call(action_key: api.action_key, params: write, capability: Integrations::Capabilities::RESTART) { :restarted }.value
  end

  test "a marker for Firefight's own restart that a model or a workflow puts in the arguments is ignored" do
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    northflank.integration_environments.create!(credentials: { token: "x" }.to_json)
    api = northflank.tools.create!(name: "api_request", description: "Call the API", enabled: true, read_only: false, params_schema: { "type" => "object" })
    Ability::Grant.create!(workspace: @workspace, principal: @run.acting_principal, action: Ability::Action.lookup(api.action_key, @workspace))
    agent_run = Workflow::AgentRun.new(run: @run, record: @step)
    Integrations::NativeExecutor.expects(:call).never

    Chat::Tools::Connection.new(agent_run, api).call("method" => "POST", "path" => "/v1/projects/shop/secrets", "capability" => Integrations::Capabilities::RESTART)

    assert_person_asked agent_run.held
  end

  test "an unattended rule never answers for a change only a person may approve" do
    rule = @workspace.unattended_rules.new(id: SecureRandom.uuid)
    @workspace.unattended_rules.stubs(:find_by).returns(rule)
    rule.stubs(:admits?).returns(true)
    Ability::Grant.create!(workspace: @workspace, principal: SystemAgent.investigator, action: Ability::Action.lookup(@secret.action_key, @workspace))

    held = assert_raises(AbilityGateway::PendingApproval) do
      AbilityGateway.authorize!(principal: SystemAgent.investigator, action_key: @secret.action_key, workspace: @workspace, params: { "name" => "TOKEN" },
                                context: { source: AbilityGateway::SOURCE_INVESTIGATION, unattended_rule_id: rule.id }) { :set }
    end
    assert_person_asked held.approval
  end

  private

  def assert_person_asked(approval)
    assert approval, "the call waits"
    assert_equal [ Ability::Approval::STATUS_PENDING, AbilityGateway::PERSON_REQUIREMENT["role"], true ],
                 [ approval.status, approval.required_role, approval.self_approvable ]
  end
end
