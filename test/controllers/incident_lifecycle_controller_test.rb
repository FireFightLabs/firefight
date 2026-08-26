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

  # Declaring

  test "the declare form is the workspace's Declare form" do
    get declare_incident_form_path
    assert_response :success

    expected = IncidentFormResolver.new(@workspace)
      .resolve(IncidentForm::SLUG_DECLARE, context: {})
      .map { |field| field.system_field_key || field.incident_field_definition.slug }

    assert_equal expected, json_response["fields"].map { |field| field["key"] }
  end

  test "declaring creates the incident and lands on its page" do
    assert_difference "@workspace.incidents.count", 1 do
      post declare_incident_path, params: { answers: declare_answers }
    end

    incident = @workspace.incidents.find_by!(name: "Checkout is failing")
    assert_redirected_to incident_path(incident)
    assert_equal "#{incident.identifier} was declared.", flash[:notice]
    assert_equal Incident::SOURCE_DASHBOARD, incident.source
    assert_equal @member, incident.declared_by
    assert_equal @workspace.incident_statuses.default_status, incident.incident_status
  end

  # Severity is fixed_required on every workspace's Declare form. Name is not,
  # this one has it configured optional, which is the point of asking the
  # resolver rather than assuming.
  test "declaring without a required answer creates nothing" do
    assert_no_difference "@workspace.incidents.count" do
      post declare_incident_path, params: { answers: declare_answers.except(:severity) }
    end

    assert_match(/required/i, flash[:alert])
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

  # A field the responder's own answers made applicable has to survive the
  # submit. Validating against the stored incident instead of the answers made
  # the form show it and then refuse it as an unknown field.
  test "a field a submitted answer brings into scope is accepted, not rejected" do
    critical = @workspace.incident_severities.active.find_by!(slug: "critical")
    @incident.update!(incident_severity: @workspace.incident_severities.active.where.not(id: critical.id).first)
    conditional_field(on_severity: critical)

    answers = update_answers.merge(severity: critical.slug, exec_comms: "sent")

    shown = IncidentFormPrompt.new(
      @workspace, incident: @incident, form_slug: IncidentForm::SLUG_UPDATE, answers: answers.stringify_keys
    ).fields.map(&:key)
    assert_includes shown, "exec_comms", "the form should offer the field once severity is Critical"

    patch incident_lifecycle_path(@incident, IncidentForm::SLUG_UPDATE), params: { answers: answers }

    assert_nil flash[:alert]
    assert_equal critical, @incident.reload.incident_severity
    assert_equal "sent", @incident.custom_fields["exec_comms"]
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

  # What a blocked control shows

  test "a live incident blocks nothing" do
    assert_nil @incident.change_blocked_reason
  end

  test "an incident that is over says why it can no longer be changed" do
    IncidentLifecycleService.new(@workspace).change_status(
      @incident, { incident_status: @workspace.incident_statuses.closed.active.first }, changed_by: @member
    )

    assert_equal "#{@incident.identifier} is closed, so it can no longer be changed.",
                 @incident.reload.change_blocked_reason
  end

  test "a canceled incident says canceled rather than closed" do
    IncidentLifecycleService.new(@workspace).change_status(
      @incident, { incident_status: @workspace.default_canceled_status }, changed_by: @member
    )

    assert_match(/is canceled/, @incident.reload.change_blocked_reason)
  end

  test "the page ships the reason so the control can explain itself" do
    IncidentLifecycleService.new(@workspace).change_status(
      @incident, { incident_status: @workspace.incident_statuses.closed.active.first }, changed_by: @member
    )

    get incident_path(@incident), headers: inertia_headers
    assert_response :success

    assert_equal @incident.reload.change_blocked_reason, inertia_props.dig("incident", "changeBlockedReason")
  end

  # The channel control

  test "an incident with no channel yet still names the one it will get" do
    incident = @workspace.incidents.create!(
      declared_by: @member, incident_status: @workspace.incident_statuses.default_status,
      incident_severity: @workspace.incident_severities.active.first,
      name: "Checkout is failing", declared_at: Time.current, source: Incident::SOURCE_DASHBOARD
    )

    get incident_path(incident), headers: inertia_headers
    assert_response :success

    assert_equal incident.generated_channel_name, inertia_props.dig("incident", "channelLabel")
    assert_nil inertia_props["channelUrl"]
  end

  test "once the channel exists the label is the real one" do
    @incident.update!(channel_name: "inc-2026-08-25-checkout", channel_id: "C123")

    get incident_path(@incident), headers: inertia_headers

    assert_equal "inc-2026-08-25-checkout", inertia_props.dig("incident", "channelLabel")
    assert_includes inertia_props["channelUrl"], "C123"
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
  # What the fixture workspace's Declare form asks for. Anything it does not
  # ask for is refused as an unknown field, so this stays exact.
  def declare_answers
    {
      name: "Checkout is failing",
      severity: @workspace.incident_severities.active.first.slug,
      summary: "EU customers only"
    }
  end

  # A custom field the workspace only asks about at one severity.
  def conditional_field(on_severity:)
    definition = @workspace.incident_field_definitions.create!(
      name: "Exec comms sent", slug: "exec_comms",
      field_type: IncidentFieldDefinition::TYPE_TEXT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_NONE,
      position: @workspace.incident_field_definitions.maximum(:position).to_i + 1
    )
    form = @workspace.incident_forms.find_by!(lifecycle_event: IncidentForm::SLUG_UPDATE)
    field = form.incident_form_fields.create!(
      field_source_kind: IncidentFormField::FIELD_SOURCE_KIND_CUSTOM,
      incident_field_definition: definition,
      visibility_mode: IncidentFormField::VISIBILITY_MODE_VISIBLE,
      required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL,
      position: 99
    )
    field.incident_conditions.create!(
      workspace: @workspace,
      condition_field: IncidentCondition::FIELD_SEVERITY,
      operator: IncidentCondition::OPERATOR_ONE_OF,
      values: [ on_severity.id ]
    )
  end

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
