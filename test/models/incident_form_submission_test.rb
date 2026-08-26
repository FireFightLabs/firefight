require "test_helper"

class IncidentFormSubmissionTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "a resolve lands on the closed status the responder picked" do
    second = @workspace.incident_statuses.create!(
      name: "Resolved with workaround", slug: "resolved_workaround",
      incident_lifecycle_stage: lifecycle_stage(IncidentLifecycleStage::CLOSED),
      position: @workspace.incident_statuses.maximum(:position).to_i + 1
    )

    attrs = submission(IncidentForm::SLUG_RESOLVE, { "status" => second.slug }).attributes

    assert_equal second, attrs[:incident_status]
  end

  test "a resolve with no status picked lands on the first closed one" do
    attrs = submission(IncidentForm::SLUG_RESOLVE, {}).attributes

    assert attrs[:incident_status].incident_lifecycle_stage.closed?
  end

  test "a cancel with no status picked lands on the workspace's canceled status" do
    attrs = submission(IncidentForm::SLUG_CANCEL, {}).attributes

    assert_equal @workspace.default_canceled_status, attrs[:incident_status]
  end

  test "a terminal form refuses when the workspace has no status for the stage" do
    @workspace.incident_statuses.canceled.update_all(deleted_at: Time.current)

    assert_raises(ActiveRecord::RecordNotFound) do
      submission(IncidentForm::SLUG_CANCEL, {}).attributes
    end
  end

  test "an update keeps the incident's own status when none was picked" do
    attrs = submission(IncidentForm::SLUG_UPDATE, {}).attributes

    assert_equal @incident.incident_status, attrs[:incident_status]
  end

  test "the summary typed while cancelling becomes the message the channel sees" do
    form = submission(IncidentForm::SLUG_CANCEL, { "summary" => "Duplicate of INC-041" })

    assert_equal "Duplicate of INC-041", form.message
    assert_equal "Duplicate of INC-041", form.attributes[:summary]
  end

  test "an update carries its own message and a resolve carries none" do
    assert_equal "Rolling back", submission(IncidentForm::SLUG_UPDATE, { "message" => "Rolling back" }).message
    assert_nil submission(IncidentForm::SLUG_RESOLVE, { "summary" => "All better" }).message
  end

  # The workspace opted out of update reminders by taking the field off the
  # form, so a submission must not quietly clear what the incident holds.
  test "next update is left alone when the form does not ask for it" do
    attrs = submission(IncidentForm::SLUG_UPDATE, {}, visible: [ "status" ]).attributes

    assert_not attrs.key?(:next_update_at)
  end

  test "next update is cleared when the form asked and nobody answered" do
    attrs = submission(IncidentForm::SLUG_UPDATE, {}, visible: [ "next_update" ]).attributes

    assert attrs.key?(:next_update_at)
    assert_nil attrs[:next_update_at]
  end

  test "next update is scheduled from the minutes picked" do
    attrs = submission(IncidentForm::SLUG_UPDATE, { "next_update" => "60" }, visible: [ "next_update" ]).attributes

    assert_in_delta 60.minutes.from_now, attrs[:next_update_at], 5
  end

  test "an incident type on the form but blanked is cleared, one never shown is untouched" do
    cleared = submission(IncidentForm::SLUG_UPDATE, {}, visible: [ "incident_type" ]).attributes
    assert cleared.key?(:incident_type)
    assert_nil cleared[:incident_type]

    untouched = submission(IncidentForm::SLUG_UPDATE, {}, visible: [ "status" ]).attributes
    assert_not untouched.key?(:incident_type)
  end

  test "custom fields ride along only when something was answered" do
    assert_not submission(IncidentForm::SLUG_UPDATE, {}).attributes.key?(:custom_fields)

    with_values = IncidentFormSubmission.new(
      @workspace, incident: @incident, form_slug: IncidentForm::SLUG_UPDATE,
      system_attrs: {}, custom_fields: { "region" => "eu" }
    )
    assert_equal({ "region" => "eu" }, with_values.attributes[:custom_fields])
  end

  test "the lead value is handed back raw for the entry point to resolve" do
    form = submission(IncidentForm::SLUG_RESOLVE, { "lead" => "U123" })

    assert_equal "U123", form.lead_value
    assert_not form.attributes.key?(:lead)
  end

  private

  def lifecycle_stage(key)
    IncidentLifecycleStage.find_by!(key: key)
  end

  def submission(slug, system_attrs, visible: nil)
    IncidentFormSubmission.new(
      @workspace,
      incident: @incident,
      form_slug: slug,
      system_attrs: system_attrs,
      visible_system_keys: visible&.to_set
    )
  end
end
