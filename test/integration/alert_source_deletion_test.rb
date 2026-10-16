require "test_helper"

# An alert source is deleted only while it holds no alerts, since its alerts are the record of what fired. Above zero it
# is turned off instead, on every surface, with the same sentence.
class AlertSourceDeletionTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @used = @workspace.alert_sources.create!(name: "Checkout", provider: AlertSource::PROVIDER_GENERIC)
    2.times do |index|
      @used.alerts.create!(workspace: @workspace, external_id: "e#{index}", fingerprint: "f#{index}", status: Alert::STATUS_RESOLVED,
                           resolved_at: 1.minute.ago, received_at: 5.minutes.ago, last_seen_at: 5.minutes.ago)
    end
    @unused = @workspace.alert_sources.create!(name: "Staging", provider: AlertSource::PROVIDER_GENERIC)
  end

  test "a source names how many alerts keep it, counted in one query for the whole list" do
    sources = @workspace.alert_sources.with_usage_counts.index_by(&:name)

    assert_equal 2, sources["Checkout"].usage_count
    assert_equal "Checkout has 2 alerts and cannot be deleted. Disable it instead.", sources["Checkout"].deletion_blocked_reason
    assert_nil sources["Staging"].deletion_blocked_reason
    assert_raises(OptionGuards::Blocked) { @used.destroy_guarded! }
    assert_equal 2, @used.alerts.count, "its alerts are never deleted with it"
  end

  test "the settings page ships why a source cannot be deleted, refuses it with a notice, and deletes one with none" do
    sign_in(users(:alice), @workspace)

    get settings_alert_sources_url, headers: inertia_headers
    rows = inertia_props["alertSources"].index_by { |row| row["name"] }
    assert_equal "Checkout has 2 alerts and cannot be deleted. Disable it instead.", rows["Checkout"]["deletionBlockedReason"]
    assert_nil rows["Staging"]["deletionBlockedReason"]

    delete alert_source_url(@used)
    assert_equal "Checkout has 2 alerts and cannot be deleted. Disable it instead.", flash[:alert]
    assert AlertSource.exists?(@used.id)

    delete alert_source_url(@unused)
    assert_equal "Staging was deleted.", flash[:notice]
    assert_not AlertSource.exists?(@unused.id)
  end

  test "the API and MCP refuse the same way" do
    _, token = ApiKey.create_with_token!(workspace: @workspace, created_by: @admin, on_behalf_of: @admin, name: "Admin")

    delete "/api/v1/alert_sources/#{@used.endpoint_path}", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :unprocessable_entity
    assert_equal "Checkout has 2 alerts and cannot be deleted. Disable it instead.", response.parsed_body.dig("error", "message")

    refused = Mcp::ToolDispatcher.call(tool: Mcp::Tools::DeleteAlertSource, server_context: { workspace: @workspace, principal: @admin },
                                       args: { slug: @used.endpoint_path })
    assert refused.error?
    assert_match "cannot be deleted. Disable it instead.", Mcp::ToolDispatcher.text_of(refused)
    assert AlertSource.exists?(@used.id)
  end
end
