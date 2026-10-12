require "application_system_test_case"

class IncidentTimelineNoteTest < ApplicationSystemTestCase
  STATEMENT = "Alice traced the 502s to the checkout service's connection pool, which ran out of connections " \
              "after the 14:02 deploy doubled the number of workers on every node in the cluster"

  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
    @incident.incident_events.create!(
      event_type: IncidentEvent::MILESTONE_NOTED,
      created_at: 10.minutes.ago,
      metadata: {
        kind: "finding",
        statement: STATEMENT,
        member_id: @member.id,
        member_name: @member.display_name,
        message_text: "*Found it* <@#{@member.platform_user_id}>: ```Customers are seeing 502s on checkout```",
        permalink: "https://slack.test/p1"
      }
    )
  end

  test "a note's statement sits on its own line below the header, and its quote renders its Slack formatting" do
    visit incident_path(@incident)

    statement = find("p", text: STATEMENT)
    header = find("span", exact_text: "noted")
    assert_operator top_of(statement), :>=, bottom_of(header)

    assert_selector "pre code", text: "Customers are seeing 502s on checkout"
    assert_selector "strong", text: "Found it"
    assert_text "@#{@member.display_name}"
    assert_no_text "```"
    assert_no_text "<@#{@member.platform_user_id}>"
  end

  private

  def top_of(element) = element.evaluate_script("this.getBoundingClientRect().top")
  def bottom_of(element) = element.evaluate_script("this.getBoundingClientRect().bottom")
end
