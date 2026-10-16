require "test_helper"

class TimelineEventSerializerFixTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
    @investigation = @incident.workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
  end

  test "a fix step shows what it produced, its link clickable where the words name it, and opens the run" do
    event = @incident.incident_events.create!(
      event_type: IncidentEvent::FIX_STEP_DONE, actor: workspace_memberships(:alice_workspace_one),
      metadata: { investigation_id: @investigation.id, position: 1, step_title: "Open a pull request with the change",
                  result: "Opened a pull request: PR #856", link_label: "PR #856", link_url: "https://github.com/FireFightLabs/firefight/pull/856" }
    )
    rendered = TimelineEventSerializer.one(@incident.timeline_events.find { |each| each.id == event.id })

    assert_equal "ran", rendered[:description]
    assert_equal "step 1 of the fix", rendered[:subject][:label]
    assert_includes rendered[:subject][:href], @investigation.id
    assert_equal({ title: "Open a pull request with the change", result: "Opened a pull request: PR #856",
                   link: { before: "Opened a pull request: ", label: "PR #856", href: "https://github.com/FireFightLabs/firefight/pull/856", after: "" } },
                 rendered[:fixStep])
    assert_nil rendered[:details]
  end

  test "a link that is not https is never made clickable" do
    event = @incident.incident_events.create!(
      event_type: IncidentEvent::FIX_STEP_DONE,
      metadata: { investigation_id: @investigation.id, position: 1, step_title: "Roll back", result: "Link: example.com",
                  link_label: "example.com", link_url: "javascript:alert(1)" }
    )

    assert_nil TimelineEventSerializer.one(event)[:fixStep][:link]
  end

  test "the answer shows the short answer first, with the full answer behind it" do
    finding = @investigation.create_finding!(
      summary: "PgBouncer `pool_size` dropped from 40 to 20 in deploy a1b2c3, so `checkout-api` waits on connections.",
      answer_kind: Investigation::Finding::KIND_ROOT_CAUSE, confidence: 0.9,
      what_is_wrong: "Checkout runs out of database connections since the 14:02 deploy.", suggested_fix: "Roll back the 14:02 deploy."
    )
    @investigation.note_answered!(finding)
    event = @incident.incident_events.find_by!(event_type: IncidentEvent::INVESTIGATION_ANSWERED)

    expected = { headline: "Root cause found", sureness: "Very sure", whatIsWrong: "Checkout runs out of database connections since the 14:02 deploy.",
                 suggestedFix: "Roll back the 14:02 deploy.", full: finding.summary }
    assert_equal expected, TimelineEventSerializer.one(event)[:answer]
    assert_equal expected, TimelineEventSerializer.one(event, answers: { event.id => finding })[:answer]
    assert_nil TimelineEventSerializer.one(event)[:details]
  end

  test "an answer noted before the short answer was kept reads it from the run the page hands in" do
    finding = @investigation.create_finding!(summary: "The deploy halved the pool. More detail.", what_is_wrong: "The pool is too small.")
    event = @incident.incident_events.create!(event_type: IncidentEvent::INVESTIGATION_ANSWERED,
                                              metadata: { investigation_id: @investigation.id, message: finding.summary })

    assert_nil TimelineEventSerializer.one(event)[:answer]
    assert_equal "The deploy halved the pool. More detail.", TimelineEventSerializer.one(event)[:details]
    assert_equal "The pool is too small.", TimelineEventSerializer.one(event, answers: { event.id => finding })[:answer][:whatIsWrong]
  end
end
