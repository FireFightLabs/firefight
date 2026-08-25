require "test_helper"

class IncidentLifecycleControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    sign_in(@member.user, @workspace)

    stub_post_message
    stub_update_message
    stub_set_channel_topic
    stub_set_channel_purpose
  end

  # Reading the form

  test "the form is the resolver's answer, not the controller's" do
    get incident_form_path(@incident, IncidentForm::SLUG_UPDATE)
    assert_response :success

    expected = IncidentFormResolver.new(@workspace)
      .resolve(IncidentForm::SLUG_UPDATE, context: IncidentConditionEvaluator.context_for(@incident))
      .map { |field| field.system_field_key || field.incident_field_definition.slug }

    assert_equal expected, json_response["fields"].map { |field| field["key"] }
  end

  test "answering a dispatching field re-resolves what is asked" do
    terminal = @workspace.incident_statuses.terminal.active.first

    get incident_form_path(@incident, IncidentForm::SLUG_UPDATE), params: { answers: { status: terminal.slug } }
    assert_response :success

    assert_not_includes json_response["fields"].map { |field| field["key"] }, IncidentSystemField::KEY_NEXT_UPDATE
  end

  test "an unknown form is refused rather than guessed at" do
    get incident_form_path(@incident, "nonsense")

    assert_response :bad_request
  end

  # Writing

  test "resolving closes the incident and records it once" do
    assert_difference -> { @incident.incident_events.where(event_type: IncidentEvent::INCIDENT_RESOLVED).count }, 1 do
      patch incident_lifecycle_path(@incident, IncidentForm::SLUG_RESOLVE), params: { answers: resolve_answers }
    end

    assert_redirected_to incident_path(@incident)
    assert_equal "#{@incident.identifier} was resolved.", flash[:notice]
    assert @incident.reload.closed?
    assert_equal "Fixed", @incident.summary
  end

  test "an update posts the message the responder wrote" do
    patch incident_lifecycle_path(@incident, IncidentForm::SLUG_UPDATE), params: { answers: update_answers }

    assert_redirected_to incident_path(@incident)
    update = @incident.incident_updates.find_by!(message: "Rolling back")
    assert_equal IncidentUpdate::UPDATED, update.update_type
  end

  test "cancelling takes the incident out of the response" do
    patch incident_lifecycle_path(@incident, IncidentForm::SLUG_CANCEL), params: { answers: {} }

    assert @incident.reload.canceled?
    assert_equal "#{@incident.identifier} was canceled.", flash[:notice]
  end

  test "a missing required answer comes back as the reason, and nothing is written" do
    patch incident_lifecycle_path(@incident, IncidentForm::SLUG_UPDATE),
          params: { answers: update_answers.merge(message: "") }

    assert_redirected_to incident_path(@incident)
    assert_match(/required/i, flash[:alert])
    assert_not @incident.reload.terminal?
  end

  # The resolver owns what a form asks. A key it did not ask for is refused
  # here for the same reason Slack refuses it, from the same call.
  test "a field the form never asked for is refused rather than written" do
    patch incident_lifecycle_path(@incident, IncidentForm::SLUG_CANCEL),
          params: { answers: { summary: "Not real" } }

    assert_match(/Unknown fields/, flash[:alert])
    assert_not @incident.reload.canceled?
  end

  # Reopening

  test "reopening a closed incident puts it back on the default live status" do
    IncidentLifecycleService.new(@workspace).change_status(
      @incident, { incident_status: @workspace.incident_statuses.closed.active.first }, changed_by: @member
    )

    patch incident_reopen_path(@incident), params: { reason: "Came back" }

    assert_redirected_to incident_path(@incident)
    assert_equal @workspace.default_live_status, @incident.reload.incident_status
  end

  test "reopening a live incident says so instead of doing nothing" do
    patch incident_reopen_path(@incident)

    assert_equal "#{@incident.identifier} is already active.", flash[:alert]
  end

  # Roles

  test "assigning a role names who holds it now" do
    role = incident_roles(:communications_lead_ws1)

    patch assign_incident_role_path(@incident), params: { role: role.slug, member_id: @member.id }

    assert_equal @member, @incident.reload.role_holder(role)
    assert_equal "#{@member.display_name} is now #{role.name}.", flash[:notice]
  end

  test "clearing a role is picking nobody" do
    role = incident_roles(:communications_lead_ws1)
    IncidentLifecycleService.new(@workspace).assign_role(@incident, role, @member, changed_by: @member)

    patch assign_incident_role_path(@incident), params: { role: role.slug, member_id: "" }

    assert_nil @incident.reload.role_holder(role)
    assert_equal "#{role.name} was cleared.", flash[:notice]
  end

  test "the lead cannot be cleared, and the refusal says why" do
    lead_role = @workspace.ensure_incident_role!(IncidentRole::SLUG_INCIDENT_LEAD)
    IncidentLifecycleService.new(@workspace).assign_role(@incident, lead_role, @member, changed_by: @member)

    patch assign_incident_role_path(@incident), params: { role: lead_role.slug, member_id: "" }

    assert_not_nil flash[:alert]
    assert_equal @member, @incident.reload.role_holder(lead_role)
  end

  # Relationships

  test "linking names both incidents on the timeline" do
    other = incidents(:active_major_ws1)

    post incident_link_path(@incident), params: { relationship: IncidentRelationship::RELATED, target_id: other.id }

    assert_redirected_to incident_path(@incident)
    assert @incident.incident_events.exists?(event_type: IncidentEvent::RELATIONSHIP_CREATED)
  end

  test "marking a duplicate cancels this one and points at the real one" do
    other = incidents(:active_major_ws1)

    post incident_link_path(@incident), params: { relationship: IncidentRelationship::DUPLICATE, target_id: other.id }

    assert @incident.reload.canceled?
    assert_equal other, @incident.duplicate_of
  end

  # Scoping

  test "another workspace's incident is not reachable" do
    other = incidents(:active_p0_ws2)

    get incident_form_path(other, IncidentForm::SLUG_UPDATE)

    assert_response :not_found
  end

  private

  # Exactly what each form asks for in the fixture workspace. Reading them off
  # the resolver rather than hardcoding would hide the thing being tested.
  def resolve_answers
    { severity: @incident.incident_severity.slug, summary: "Fixed" }
  end

  def update_answers
    {
      message: "Rolling back",
      status: @incident.incident_status.slug,
      severity: @incident.incident_severity.slug
    }
  end

  def json_response
    JSON.parse(response.body)
  end
end
