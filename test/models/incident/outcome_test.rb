require "test_helper"

class Incident::OutcomeTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:resolved_minor_ws1)
  end

  test "a completed postmortem says how it ended, before the incident's own summary" do
    @incident.postmortem.update!(status: Postmortem::STATUS_COMPLETED, summary: "A bad deploy broke uploads. It was rolled back.")

    outcome = Incident.find(@incident.id).outcome

    assert_equal [ "A bad deploy broke uploads.", Incident::Outcome::SOURCE_POSTMORTEM ], [ outcome.text, outcome.source ]
  end

  test "a draft postmortem is not an outcome, so the incident's summary is, then the running summary" do
    @incident.postmortem.update!(status: Postmortem::STATUS_DRAFT, summary: "Not finished")
    assert_equal Incident::Outcome::SOURCE_SUMMARY, Incident.find(@incident.id).outcome.source

    @incident.update!(summary: nil)
    @incident.workspace.update!(transcript_access_enabled: true)
    IncidentSummary.create!(incident: @incident, workspace: @incident.workspace, content: "Uploads failed after the 14:02 deploy and recovered on rollback.",
                            summary_up_to_ts: "1.1", generated_at: Time.current, model: "test")
    outcome = Incident.find(@incident.id).outcome
    assert_equal [ "Uploads failed after the 14:02 deploy and recovered on rollback.", Incident::Outcome::SOURCE_RUNNING_SUMMARY ], [ outcome.text, outcome.source ]
  end

  test "the running summary is used only where transcripts may be read, and never for a private incident" do
    @incident.update!(summary: nil)
    IncidentSummary.create!(incident: @incident, workspace: @incident.workspace, content: "Uploads failed after the deploy.",
                            summary_up_to_ts: "1.1", generated_at: Time.current, model: "test")

    @incident.workspace.update!(transcript_access_enabled: false)
    assert_nil Incident.find(@incident.id).outcome

    @incident.workspace.update!(transcript_access_enabled: true)
    @incident.update!(is_private: true)
    assert_nil Incident.find(@incident.id).outcome
  end

  test "a deleted incident is not a past incident" do
    auth = catalog_entries(:auth_service)
    IncidentFieldValue.create!(incident: @incident, incident_field_definition: incident_field_definitions(:affected_services_ws1), catalog_entry: auth)
    @incident.update_columns(deleted_at: Time.current)

    assert_empty Incident.past_on(@incident.workspace, [ auth.id ])
  end

  test "a long outcome is cut to one short line, and nothing written is no outcome" do
    @incident.update!(summary: "word " * 100)
    assert_operator Incident.find(@incident.id).outcome.text.length, :<=, Incident::Outcome::OUTCOME_LENGTH

    @incident.update!(summary: nil)
    assert_nil Incident.find(@incident.id).outcome
  end

  test "past incidents are the ended ones on those catalog entries in the last six months, never an open one" do
    auth = catalog_entries(:auth_service)
    definition = incident_field_definitions(:affected_services_ws1)
    IncidentFieldValue.create!(incident: @incident, incident_field_definition: definition, catalog_entry: auth)
    IncidentFieldValue.create!(incident: incidents(:active_critical_ws1), incident_field_definition: definition, catalog_entry: auth)

    assert_equal [ @incident ], Incident.past_on(@incident.workspace, [ auth.id ]).map(&:incident)

    @incident.update_columns(resolved_at: 200.days.ago)
    assert_empty Incident.past_on(@incident.workspace, [ auth.id ])
  end
end
