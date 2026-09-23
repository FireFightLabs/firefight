require "test_helper"

class Investigation::RunningCodeTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @investigation = @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
  end

  test "a service with no repository in the catalog says so rather than guessing one" do
    seed(services: [ { "name" => "Auth Service", "repository" => nil } ])

    found = Investigation::RunningCode.new(@investigation).note!.fetch(Investigation::RunningCode::KEY).sole

    assert_equal Investigation::RunningCode::NOT_ON_CATALOG, found["found"]
  end

  test "without a code host that can answer, the facts say what to connect" do
    seed(services: [ { "name" => "Auth Service", "repository" => "acme/auth" } ])

    found = Investigation::RunningCode.new(@investigation).note!.fetch(Investigation::RunningCode::KEY).sole

    assert_equal Investigation::RunningCode::NOT_CONNECTED, found["found"]
  end

  test "it asks through the same tool the agent would, as a numbered step, once" do
    seed(services: [ { "name" => "Auth Service", "repository" => "acme/auth" } ])
    tool = github_running_commit_tool
    Chat::Tools::Connection.any_instance.expects(:call)
      .with("repo" => "acme/auth", "at" => @incident.declared_at.iso8601)
      .returns("<tool_result tool=\"github_running_commit\" step=\"1\">Running in acme/auth: a1b2c3</tool_result>")
      .once

    Investigation::RunningCode.new(@investigation).note!
    Investigation::RunningCode.new(@investigation.reload).note!

    found = @investigation.reload.seed_pack.fetch(Investigation::RunningCode::KEY).sole
    assert_match "a1b2c3", found["found"]
    assert tool.persisted?
  end

  private

  def seed(services:)
    @investigation.update!(seed_pack: { "incident" => {}, "services" => services })
  end

  def github_running_commit_tool
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: Integrations::GithubApp::PROVIDER_KEY, name: "GitHub")
    integration.integration_environments.create!(base_config: { "installation_id" => "1" })
    integration.tools.create!(
      name: Integrations::Packs::Github::RUNNING_COMMIT, description: "Which commit was running", read_only: true, enabled: true,
      params_schema: { "type" => "object", "properties" => {} }
    )
  end
end
