require "test_helper"

# How what happens to a page in an on-call tool reads on the incident's timeline, on the dashboard and in Slack.
class Incident::PageTimelineTest < ActiveSupport::TestCase
  include PagingTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @page = @incident.pages.create!(workspace: @workspace, integration: connect_pagerduty!(@workspace), origin: Incident::Page::ORIGIN_RAISED,
                                    state: Incident::Page::STATE_TRIGGERED, external_id: "PGR0VU2", reference: "#42",
                                    url: "https://acme.pagerduty.com/incidents/PGR0VU2", target: "Checkout")
  end

  test "someone in the tool is named, and the page opens in the tool from the dashboard" do
    @page.record_event!(IncidentEvent::PAGE_NOTED, by_name: "Ana Diaz", subject: @page.label, message: "Rolled back <the> deploy")

    rendered = TimelineEventSerializer.one(@incident.timeline_events.find { |event| event.event_type == IncidentEvent::PAGE_NOTED })

    assert_equal [ "Ana Diaz", false, "added a note to" ], rendered.values_at(:actor, :automated, :description)
    assert_equal({ label: "#42 in PagerDuty", href: "https://acme.pagerduty.com/incidents/PGR0VU2", external: true }, rendered[:subject])
    assert_equal "Rolled back <the> deploy", rendered[:details]
  end

  test "Slack shows the page as a link, the person by name and what they wrote, escaped" do
    event = @page.record_event!(IncidentEvent::PAGE_ACKNOWLEDGED, by_name: "Ana <Diaz>", subject: @page.label)
    noted = @page.record_event!(IncidentEvent::PAGE_NOTED, by_name: "Ana Diaz", subject: @page.label, message: "Rolled back <!channel>")

    block = Slack::IncidentTimelineFormatter.to_block(event)
    assert_includes block[:section][:text][:text], "*Page acknowledged*\n<https://acme.pagerduty.com/incidents/PGR0VU2|#42 in PagerDuty>"
    assert_includes block[:context][:elements].first[:text], "Ana &lt;Diaz&gt;"
    assert_includes Slack::IncidentTimelineFormatter.to_block(noted)[:section][:text][:text], "&lt;!channel&gt;"
  end

  test "the incident page lists each page with where it stands and why the tool did not take a change" do
    @page.update!(state: Incident::Page::STATE_RESOLVED, sync_note: "PagerDuty answered 403: Access Denied")
    held = @incident.pages.create!(workspace: @workspace, integration: @page.integration, origin: Incident::Page::ORIGIN_RAISED,
                                   state: Incident::Page::STATE_AWAITING_APPROVAL, target: "Payments")

    pages = IncidentDetailSerializer.one(@incident)[:pages]

    assert_equal [ [ "#42 in PagerDuty", "Resolved", "handled", "PagerDuty answered 403: Access Denied" ],
                   [ "A page to Payments in PagerDuty", "Waiting for approval", "problem", nil ] ],
                 pages.map { |page| page.values_at(:label, :stateWords, :tone, :note) }
    assert_equal held.id, pages.last[:id]
  end

  test "a page an alert brought in reads by its title, and one still being raised by where it goes" do
    adopted = @incident.pages.create!(workspace: @workspace, alert_source: pagerduty_source!(@workspace), origin: Incident::Page::ORIGIN_ALERT,
                                      state: Incident::Page::STATE_TRIGGERED, external_id: "PADOPTED", title: "Checkout failing")
    raising = @incident.pages.create!(workspace: @workspace, integration: @page.integration, origin: Incident::Page::ORIGIN_RAISED,
                                      state: Incident::Page::STATE_RAISING, target: "Payments")

    assert_equal "Checkout failing in PagerDuty webhooks", adopted.label
    assert_equal "a page to Payments in PagerDuty", raising.label
  end
end
