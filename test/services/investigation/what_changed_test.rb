require "test_helper"

class Investigation::WhatChangedTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @investigation = @incident.investigations.live.first || @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    @investigation.update!(seed_pack: { "incident" => {} }, brief: Investigation::Brief.from(
      { "names" => [ "checkout" ], "error_text" => "PoolExhausted" }, source: Investigation::Brief::SOURCE_CHAT
    ))
  end

  test "without a code host that can answer, the facts say what to connect and still keep the clues" do
    facts = Investigation::WhatChanged.new(@investigation).note!

    assert_equal Investigation::WhatChanged::NOT_CONNECTED, facts[Investigation::WhatChanged::KEY]
    assert_includes facts[Investigation::WhatChanged::CLUES_KEY]["names"].map { |clue| clue["value"] }, "checkout"
  end

  test "it hands the clues to the same tool the agent would call, as a numbered step, once" do
    changes_before_tool
    Chat::Tools::Connection.any_instance.expects(:call).with do |arguments|
      arguments["names"] == [ "checkout" ] && arguments["error_texts"] == [ "PoolExhausted" ] &&
        arguments["window_hours"] == Investigation::WhatChanged::ESTIMATED_WINDOW_HOURS
    end.returns("<tool_result tool=\"github_changes_before\" step=\"1\">Suspects...</tool_result>").once

    Investigation::WhatChanged.new(@investigation).note!
    Investigation::WhatChanged.new(@investigation.reload).note!

    assert_match "Suspects", @investigation.reload.seed_pack[Investigation::WhatChanged::KEY]
  end

  test "every GitHub connection is read, since each sees its own repositories" do
    changes_before_tool(name: "GitHub Acme")
    changes_before_tool(name: "GitHub Acme Labs")
    Chat::Tools::Connection.any_instance.expects(:call).twice.returns("Suspects in one org", "Suspects in the other")

    facts = Investigation::WhatChanged.new(@investigation).note!

    assert_match "Suspects in one org", facts[Investigation::WhatChanged::KEY]
    assert_match "Suspects in the other", facts[Investigation::WhatChanged::KEY]
  end

  private

  def changes_before_tool(name: "GitHub")
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: Integrations::GithubApp::PROVIDER_KEY, name: name)
    integration.integration_environments.create!(base_config: { "installation_id" => "1" })
    integration.tools.create!(
      name: Integrations::Packs::Github::CHANGES_BEFORE, description: "What changed before", read_only: true, enabled: true,
      params_schema: { "type" => "object", "properties" => {} }
    )
  end
end
