require "test_helper"

class Integrations::MitigationReaders::UpstashTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    upstash = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "upstash", name: "Upstash", slug: "upstash",
                                              settings: { "server_url" => "https://mcp.upstash.com/mcp" })
    @schedule = upstash.tools.create!(name: "qstash_manage_schedule", description: "Schedules", enabled: true, read_only: false,
                                      params_schema: { "type" => "object", "properties" => { "action" => { "enum" => %w[create get delete pause resume] },
                                                                                            "scheduleId" => { "type" => "string" } } })
  end

  test "pausing a QStash schedule is a change customers feel, undone by starting it again, and resuming or deleting one is not" do
    assert Integrations::Mitigations.call?(@schedule, { "action" => "pause", "scheduleId" => "scd_1", "region" => "eu" })
    assert_equal Integrations::Mitigations::STARTS_AGAIN, Integrations::Mitigations.undo_words(@schedule, { "action" => "pause", "scheduleId" => "scd_1" })
    assert_not Integrations::Mitigations.call?(@schedule, { "action" => "resume", "scheduleId" => "scd_1" })
    assert_not Integrations::Mitigations.call?(@schedule, { "action" => "delete", "scheduleId" => "scd_1" })
    assert_nil Integrations::Mitigations.undo_words(@schedule, { "action" => "delete", "scheduleId" => "scd_1" })
  end

  test "a tool that names its action another way, or offers no pause, is told from what it reports" do
    @schedule.update!(params_schema: { "type" => "object", "properties" => { "operation" => { "enum" => %w[create update pause resume delete] } } })
    assert Integrations::Mitigations.call?(@schedule, { "operation" => "pause" })

    @schedule.update!(params_schema: { "type" => "object", "properties" => { "action" => { "type" => "string" } } })
    assert_not Integrations::Mitigations.call?(@schedule, { "action" => "pause" })
  end
end
