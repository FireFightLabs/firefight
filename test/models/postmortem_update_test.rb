require "test_helper"

class PostmortemUpdateTest < ActiveSupport::TestCase
  test "belongs to postmortem" do
    update = postmortem_updates(:postmortem_update_generated_ws1)
    assert_equal postmortems(:postmortem_resolved_ws1), update.postmortem
  end

  test "belongs to incident" do
    update = postmortem_updates(:postmortem_update_generated_ws1)
    assert_equal incidents(:resolved_minor_ws1), update.incident
  end

  test "belongs to edited_by membership" do
    update = postmortem_updates(:postmortem_update_generated_ws1)
    assert_equal workspace_memberships(:alice_workspace_one), update.edited_by
  end

  test "validates update_type inclusion" do
    update = postmortem_updates(:postmortem_update_generated_ws1)
    update.update_type = "invalid"
    assert_not update.valid?
  end

  test "validates title presence" do
    update = postmortem_updates(:postmortem_update_generated_ws1)
    update.title = nil
    assert_not update.valid?
  end

  test "validates content presence" do
    update = postmortem_updates(:postmortem_update_generated_ws1)
    update.content = nil
    assert_not update.valid?
  end

  test "validates status presence" do
    update = postmortem_updates(:postmortem_update_generated_ws1)
    update.status = nil
    assert_not update.valid?
  end

  test "has one incident_event as eventable" do
    update = postmortem_updates(:postmortem_update_generated_ws1)
    incident = incidents(:resolved_minor_ws1)
    member = workspace_memberships(:alice_workspace_one)

    event = incident.incident_events.create!(
      event_type: IncidentEvent::POSTMORTEM_GENERATED,
      actor: member,
      eventable: update
    )

    assert_equal update, event.eventable
    assert_equal event, update.reload.incident_event
  end

  test "a revision stored before generated drafts were sanitized reaches the dashboard sanitized" do
    update = postmortem_updates(:postmortem_update_generated_ws1)
    update.content = { "html" => "<p>Checkout</p><img src=x onerror=alert(1)>" }

    assert_equal "<p>Checkout</p>", PostmortemUpdateSerializer.one(update).as_json["htmlContent"]
  end
end
