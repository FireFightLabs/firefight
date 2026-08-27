require "test_helper"

class IncidentEventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @note = @incident.incident_events.create!(
      event_type: IncidentEvent::MILESTONE_NOTED,
      metadata: { kind: "finding", statement: "Alice confirmed the pool is exhausted", message_id: "1.001" }
    )
  end

  test "dismissing a note records who did it and confirms" do
    sign_in(@member.user, @workspace)

    patch dismiss_incident_event_path(@incident, @note)

    assert_redirected_to incident_path(@incident)
    assert_equal "The note was dismissed.", flash[:notice]
    assert @note.reload.dismissed?
    assert_equal @member.id, @note.metadata["dismissed_by_member_id"]
    assert_equal @member.display_name, @note.metadata["dismissed_by_name"]
  end

  test "a dismissed note leaves the timeline the API and the AI context" do
    sign_in(@member.user, @workspace)

    patch dismiss_incident_event_path(@incident, @note)

    types = @incident.to_full_context[:timeline_events].map { |event| event[:type] }
    assert_not_includes types, IncidentEvent::MILESTONE_NOTED
  end

  test "a dismissed note is still on the incident page, marked dismissed" do
    sign_in(@member.user, @workspace)
    patch dismiss_incident_event_path(@incident, @note)

    get incident_path(@incident), headers: timeline_headers
    assert_response :success

    rendered = inertia_props["timelineEvents"].find { |event| event["id"] == @note.id }
    assert_not_nil rendered
    assert_not_nil rendered.dig("milestone", "dismissedAt")
    assert_equal @member.display_name, rendered.dig("milestone", "dismissedBy")
  end

  test "an event that is not an AI note refuses to be dismissed" do
    sign_in(@member.user, @workspace)
    pin = @incident.incident_events.create!(event_type: IncidentEvent::MESSAGE_PINNED, metadata: {})

    patch dismiss_incident_event_path(@incident, pin)

    assert_redirected_to incident_path(@incident)
    assert_equal "Only AI-noted milestones can be dismissed.", flash[:alert]
  end

  test "a note in another workspace is not reachable" do
    other = workspace_memberships(:alice_workspace_two)
    sign_in(other.user, workspaces(:slack_workspace_two))

    patch dismiss_incident_event_path(@incident, @note)

    assert_response :not_found
    assert_not @note.reload.dismissed?
  end

  test "signing in is required" do
    patch dismiss_incident_event_path(@incident, @note)

    assert_response :redirect
    assert_not @note.reload.dismissed?
  end

  private

  # timelineEvents is a deferred prop, so it only arrives on the follow-up
  # partial reload the page makes for it.
  def timeline_headers
    inertia_headers.merge(
      "X-Inertia-Partial-Data" => "timelineEvents",
      "X-Inertia-Partial-Component" => "incidents/index"
    )
  end
end
