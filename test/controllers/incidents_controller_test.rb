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
end
