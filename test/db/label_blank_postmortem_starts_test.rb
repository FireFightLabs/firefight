require "test_helper"
require Rails.root.join("db/migrate/20261007220000_label_blank_postmortem_starts")

class LabelBlankPostmortemStartsTest < ActiveSupport::TestCase
  setup do
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "a blank start recorded as generated becomes a blank start, and an AI draft stays generated" do
    blank_postmortem, blank_event = recorded_as_generated(incidents(:active_critical_ws1), html: "")
    drafted_postmortem, drafted_event = recorded_as_generated(incidents(:active_major_ws1), html: "<h2>Summary</h2>\n<p>Pool</p>")

    2.times { ActiveRecord::Migration.suppress_messages { LabelBlankPostmortemStarts.new.migrate(:up) } }

    assert_equal IncidentEvent::POSTMORTEM_STARTED, blank_event.reload.event_type
    assert_equal PostmortemUpdate::STARTED, blank_postmortem.postmortem_updates.sole.update_type
    assert_equal IncidentEvent::POSTMORTEM_GENERATED, drafted_event.reload.event_type
    assert_equal PostmortemUpdate::GENERATED, drafted_postmortem.postmortem_updates.sole.update_type
  end

  test "a revision already labelled a blank start gets its event renamed too" do
    postmortem, event = recorded_as_generated(incidents(:active_critical_ws1), html: "")
    postmortem.postmortem_updates.sole.update_columns(update_type: PostmortemUpdate::STARTED)

    ActiveRecord::Migration.suppress_messages { LabelBlankPostmortemStarts.new.migrate(:up) }

    assert_equal IncidentEvent::POSTMORTEM_STARTED, event.reload.event_type
  end

  private

  # How a postmortem was recorded before a blank start had its own event.
  def recorded_as_generated(incident, html:)
    incident.postmortem&.destroy!
    postmortem = Postmortem.create!(incident: incident, generated_by: @member, title: "#{incident.identifier} Postmortem",
                                    status: Postmortem::STATUS_DRAFT, content: { "html" => html })
    postmortem.record_change!(IncidentEvent::POSTMORTEM_GENERATED, by: @member)
    [ postmortem, incident.incident_events.find_by!(event_type: IncidentEvent::POSTMORTEM_GENERATED) ]
  end
end
