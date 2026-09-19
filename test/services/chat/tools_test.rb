require "test_helper"

class Chat::ToolsTest < ActiveSupport::TestCase
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

  test "the agent starts with only the three tools it always needs" do
    grant!(@tool)

    names = Investigation::Tools.for(@investigation, offer: ->(_tools) { }).map(&:name)

    assert_equal [ "find_tools", "record_hypothesis", "conclude" ], names
  end

  test "finding a tool the agent may use offers it to the chat and says it is ready" do
    grant!(@tool)
    offered = []
    find = Chat::Tools::Find.new(@investigation, offer: ->(tools) { offered.concat(tools) })

    answer = find.execute(query: "echoes text")

    assert_match "fake_echo_text", answer
    assert_match "ready to call", answer
    assert_equal [ "fake_echo_text" ], offered.map(&:name)
  end

  test "a tool the workspace never granted is named rather than hidden" do
    find = Chat::Tools::Find.new(@investigation, offer: ->(_tools) { })

    answer = find.execute(query: "echoes text")

    assert_match "fake_echo_text", answer
    assert_match "not granted", answer
  end

  test "Firefight's own tools are found the same way, and a granted one becomes callable" do
    grant_system!(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_READ)
    offered = []
    find = Chat::Tools::Find.new(@investigation, offer: ->(tools) { offered.concat(tools) })

    answer = find.execute(query: "search incidents")

    assert_match Mcp::Tools::SEARCH_INCIDENTS, answer
    assert_includes offered.map(&:name), Mcp::Tools::SEARCH_INCIDENTS
  end

  test "a provider nobody connected is named as not connected" do
    find = Chat::Tools::Find.new(@investigation, offer: ->(_tools) { })

    assert_match "not connected", find.execute(query: "datadog")
  end

  test "a search that matches nothing tells the agent to say so rather than guess" do
    find = Chat::Tools::Find.new(@investigation, offer: ->(_tools) { })

    assert_match "Say what you could not check", find.execute(query: "zzzz")
  end

  test "a found Firefight tool runs through the gateway and answers with what it found" do
    grant_system!(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_READ)
    tool = Chat::Tools.catalog(@investigation).find { |entry| entry.name == Mcp::Tools::SEARCH_INCIDENTS }.tool

    result = tool.call(query: @incident.identifier)

    assert_match @incident.identifier, result
    step = @investigation.steps.sole
    assert_equal Ability::Action.system_key(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_READ), step.action_key
    assert_equal Investigation::Step::STATUS_SUCCEEDED, step.status
  end

  test "a connection tool runs through the gateway and returns what the provider said" do
    grant!(@tool)
    tool = Chat::Tools.catalog(@investigation).find { |entry| entry.name == "fake_echo_text" }.tool

    result = tool.call(text: "hi")

    assert_equal "echo: hi", result
    assert_equal "fake.echo_text", @investigation.steps.sole.action_key
  end

  test "a refused call comes back as a result the agent can work around" do
    tool = Chat::Tools::Connection.new(@investigation, @tool)

    result = tool.call(text: "hi")

    assert_match "Not allowed", result
    assert_equal Investigation::Step::STATUS_FAILED, @investigation.steps.sole.status
  end

  test "a provider failure is reported to the agent rather than ending the run" do
    grant!(@tool)
    Integrations::NativeExecutor.stubs(:call).raises(Integrations::Error, "GitHub said no")
    tool = Chat::Tools.catalog(@investigation).find { |entry| entry.name == "fake_echo_text" }.tool

    assert_match "GitHub said no", tool.call(text: "hi")
  end

  test "the model sees each tool's own description and parameters" do
    grant!(@tool)
    tool = Chat::Tools.catalog(@investigation).find { |entry| entry.name == "fake_echo_text" }.tool

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

  def grant_system!(resource, action)
    Ability::Grant.create!(
      workspace: @workspace, principal: @investigation.acting_principal,
      action: Ability::Action.system!(Ability::Action.system_key(resource, action))
    )
    bust_grants!
  end

  def grant!(tool)
    Ability::Grant.create!(
      workspace: @workspace, principal: @investigation.acting_principal, action: tool.reload.ability_action
    )
    bust_grants!
  end

  def bust_grants!
    principal = @investigation.acting_principal
    Ability::Resolver.bust!(
      principal_type: principal.class.polymorphic_name, principal_id: principal.id, workspace_id: @workspace.id
    )
  end
end
