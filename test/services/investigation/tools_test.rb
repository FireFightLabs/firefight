require "test_helper"

class Investigation::ToolsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @investigation = @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: 10, max_spend_cents: 400
    )

    @integration = @workspace.integrations.create!(
      kind: Integration::KIND_NATIVE, provider: "fake", name: "Fake"
    )
    @integration.integration_environments.create!(
      catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json
    )
    @tool = @integration.tools.create!(
      name: "echo_text", description: "Echoes text back", read_only: true, enabled: true,
      params_schema: { "type" => "object", "properties" => { "text" => { "type" => "string" } } }
    )
    Integrations::NativePack.stubs(:for).with("fake").returns(FakeNativePack)
  end

  test "the agent is offered the tools it was granted, and never the ones it was not" do
    grant!(@tool)

    names = Investigation::Tools.for(@investigation).map(&:name)

    assert_includes names, "fake_echo_text"
    assert_includes names, "conclude"
    assert_includes names, "record_hypothesis"
  end

  test "a tool the agent holds no grant for is not offered" do
    assert_empty Investigation::Tools.connection_tools(@investigation)
  end

  test "a connection tool runs through the gateway and returns what the provider said" do
    grant!(@tool)
    tool = Investigation::Tools.connection_tools(@investigation).first

    result = tool.call(text: "hi")

    assert_equal "echo: hi", result
    step = @investigation.steps.sole
    assert_equal "fake.echo_text", step.action_key
    assert_equal({ "text" => "hi" }, step.params)
    assert_equal "echo: hi", step.raw_result
    assert_equal Ability::Invocation::OUTCOME_SUCCESS, Ability::Invocation.find(step.invocation_id).outcome
  end

  test "a refused call comes back as a result the agent can work around" do
    tool = Investigation::Tools::Connection.new(@investigation, @tool)

    result = tool.call(text: "hi")

    assert_match "Not allowed", result
    assert_equal Investigation::Step::STATUS_FAILED, @investigation.steps.sole.status
  end

  test "a provider failure is reported to the agent rather than ending the run" do
    grant!(@tool)
    Integrations::NativeExecutor.stubs(:call).raises(Integrations::Error, "GitHub said no")
    tool = Investigation::Tools.connection_tools(@investigation).first

    assert_match "GitHub said no", tool.call(text: "hi")
  end

  test "the model describes a tool by the connection's own schema" do
    grant!(@tool)
    tool = Investigation::Tools.connection_tools(@investigation).first

    assert_equal @tool.params_schema, tool.parameters_schema
    assert_equal "Echoes text back", tool.description
  end

  test "recording a theory writes it once and updates it after that" do
    tool = Investigation::Tools::RecordHypothesis.new(@investigation)

    tool.execute(assertion: "The 14:02 deploy did it")
    tool.execute(assertion: "The 14:02 deploy did it", status: Investigation::Hypothesis::STATUS_SUPPORTED, confidence: 0.8)

    hypothesis = @investigation.hypotheses.sole
    assert_equal Investigation::Hypothesis::STATUS_SUPPORTED, hypothesis.status
    assert_equal 0.8, hypothesis.confidence.to_f
    assert_equal 1, hypothesis.position
  end

  test "concluding writes the answer against the theory it names" do
    @investigation.record_hypothesis!(assertion: "The 14:02 deploy did it")
    tool = Investigation::Tools::Conclude.new(@investigation)

    tool.execute(
      summary: "The deploy raised the pool size", hypothesis: "The 14:02 deploy did it",
      evidence: [ "commit abc123" ], gaps: "Could not read the logs"
    )

    finding = @investigation.reload.finding
    assert_equal "The deploy raised the pool size", finding.summary
    assert_equal "The 14:02 deploy did it", finding.winning_hypothesis.assertion
    assert_equal [ "commit abc123" ], finding.evidence
    assert_equal "Could not read the logs", finding.gaps
    assert_equal Investigation::Finding::STATE_UNPUBLISHED, finding.published_state
  end

  test "concluding with no theory still records the answer" do
    Investigation::Tools::Conclude.new(@investigation).execute(summary: "Nothing in the evidence explains it")

    assert_nil @investigation.reload.finding.winning_hypothesis
  end

  private

  def grant!(tool)
    Ability::Grant.create!(
      workspace: @workspace, principal: @investigation.agent_principal, action: tool.reload.ability_action
    )
    principal = @investigation.agent_principal
    Ability::Resolver.bust!(
      principal_type: principal.class.polymorphic_name, principal_id: principal.id, workspace_id: @workspace.id
    )
  end
end
