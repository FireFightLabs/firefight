require "test_helper"

class IncidentsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  fixtures :workspaces, :users, :workspace_memberships, :incidents, :postmortems,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
    sign_in(@user, @workspace)
  end

  test "ai_rewrite_postmortem returns 402 with the denial message and runs no AI when blocked" do
    message = deny_entitlements!("Your trial has ended — upgrade to keep using AI.")
    incident = incidents(:resolved_minor_ws1) # has postmortem_resolved_ws1

    FirefightAi::PostmortemSectionRewriter.any_instance.expects(:rewrite).never

    post incident_postmortem_ai_rewrite_path(incident_id: incident.id),
      params: { selected_html: "<p>x</p>", instruction: "tighten" }, as: :json

    assert_response :payment_required
    assert_equal message, response.parsed_body["error"]
  end

  test "generate_postmortem redirects with the denial message and enqueues no job when blocked" do
    message = deny_entitlements!("Your trial has ended — upgrade to keep using AI.")
    incident = Incident.create!(
      workspace: @workspace,
      declared_by: workspace_memberships(:alice_workspace_one),
      incident_status: incident_statuses(:resolved_ws1),
      incident_severity: incident_severities(:critical_ws1),
      name: "Closed, no postmortem",
      is_private: false,
      source: Incident::SOURCE_SLACK,
      resolved_at: 1.hour.ago
    )

    assert_no_enqueued_jobs do
      post incident_postmortem_generate_path(incident_id: incident.id)
    end

    assert_redirected_to incident_path(incident)
    assert_equal message, flash[:alert]
    assert_nil incident.reload.postmortem
  end

  private

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end

  test "the incident page names who declared it" do
    incident = incidents(:active_critical_ws1)

    get incident_path(incident), headers: inertia_headers

    assert_response :success
    declared_by = inertia_props["incident"]["declaredBy"]
    assert_equal incident.declared_by.user.name, declared_by["name"]
    assert declared_by["initials"].present?
  end

  # Serializing must not reach for the declarer per row. Dropping declared_by
  # from with_list_associations makes this fail.
  test "the incidents table names who declared each one from the preload" do
    seen = []
    counter = ->(_, _, _, _, payload) { seen << payload[:sql] unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get dashboard_path, headers: inertia_headers }

    assert_response :success
    rows = inertia_props["incidents"]
    incident = incidents(:active_critical_ws1)
    assert rows.length > 1, "expected more than one incident to prove the preload"
    assert_equal incident.declared_by.user.name, rows.find { |row| row["id"] == incident.id }["declaredBy"]

    single_row_lookups = seen.count { |sql| sql.match?(/FROM "(users|workspace_memberships)".*"id" = \$1/m) }
    assert_equal 0, single_row_lookups,
      "#{single_row_lookups} per-row lookups of the declarer; with_list_associations should preload them"
  end
end
