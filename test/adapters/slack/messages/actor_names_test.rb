require "test_helper"

# Whoever has no Slack account, a person who joined by email, an agent or an API key, is named in every message that
# credits an actor, never shown as an empty <@> mention.
class Slack::Messages::ActorNamesTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @web_only = @workspace.workspace_memberships.create!(
      user: User.create!(email: "web-only@example.com", name: "Wendy Web"), role: :member, joined_at: Time.current
    )
    @agent = @workspace.agents.create!(name: "Triage agent", slug: "triage_agent")
  end

  test "status updates, cancellations, resolutions and reopens name the actor" do
    update = text_of(Slack::Messages::StatusUpdate.build(@incident, message: "x", updated_by_platform_user_id: nil, updated_by_name: "Wendy Web", scope: :inline))
    resolved = text_of(Slack::Messages::Resolution.build(@incident, resolved_by_platform_user_id: nil, resolved_by_name: "Triage agent"))
    resolved_thread = text_of(Slack::Messages::Resolution.announcement_thread(@incident, resolved_by_platform_user_id: nil, resolved_by_name: "Wendy Web"))
    reopened = text_of(Slack::Messages::Reopen.build(@incident, reopened_by_platform_user_id: nil, reopened_by_name: "Wendy Web"))
    reopened_thread = text_of(Slack::Messages::Reopen.announcement_thread(@incident, reopened_by_platform_user_id: nil, reopened_by_name: "Wendy Web"))

    assert_includes update, "Updated by *Wendy Web*"
    assert_includes resolved, "Resolved by *Triage agent*"
    assert_includes resolved_thread, "Resolved by: *Wendy Web*"
    assert_includes reopened, "Reopened by *Wendy Web*"
    assert_includes reopened_thread, "Reopened by: *Wendy Web*"
    [ update, resolved, resolved_thread, reopened, reopened_thread ].each { |text| assert_not_includes text, "<@>" }
  end

  test "a person with a Slack account is still mentioned" do
    resolved_thread = text_of(Slack::Messages::Resolution.announcement_thread(@incident, resolved_by_platform_user_id: "U1", resolved_by_name: "Alice"))

    assert_includes resolved_thread, "Resolved by: *<@U1>*"
  end

  test "the lead announcement and the incident details name a lead and a declarer with no Slack account" do
    @incident.lead = @web_only
    @incident.update!(declared_by: @agent)

    lead = text_of(Slack::Messages::LeadAssignment.announcement(lead_platform_user_id: nil, lead_name: "Wendy Web"))
    details = text_of(Slack::Messages::IncidentDetail.for_incident(@incident.reload))
    postmortem = text_of(Slack::Messages::Postmortem.build(@incident, Postmortem.new(title: "Review")))

    assert_includes lead, "*Wendy Web* is now the *Incident Lead*"
    assert_includes details, "*Lead:* *Wendy Web*"
    assert_includes details, "*Declared by:* *Triage agent*"
    assert_includes postmortem, "Lead: *Wendy Web*"
  end

  test "a role given to someone with no Slack account reads as assigned to them" do
    changes = [ { role_name: "Comms", platform_user_id: nil, name: "Wendy Web" }, { role_name: "Scribe", platform_user_id: nil, name: nil } ]

    assert_includes text_of(Slack::Messages::RoleAssignment.announcement(changes)), "*Comms*: *Wendy Web*"
    assert_equal "Comms assigned, Scribe cleared", Slack::Messages::RoleAssignment.summary_text(changes)
  end

  test "the timeline names an agent instead of calling it the system" do
    event = @incident.incident_events.create!(event_type: IncidentEvent::MESSAGE_PINNED, actor: @agent, metadata: {})

    assert_includes text_of(Slack::IncidentTimelineFormatter.to_block(event)), "*Triage agent*"
  end

  test "the lifecycle hands the actor's name to the messages it starts" do
    IncidentUpdateWorkflow.expects(:start!).with(@incident, has_entry(context: has_entries(updated_by_platform_user_id: nil, updated_by_name: "Wendy Web")))

    IncidentLifecycleService.new(@workspace).change_status(@incident, { summary: "New summary" }, changed_by: @web_only)
  end

  private

  # Every text a block holds, joined, so an assertion reads the words Slack shows.
  def text_of(blocks)
    case blocks
    when Array then blocks.map { |block| text_of(block) }.join("\n")
    when Hash then blocks.map { |key, value| key.to_s == "text" && value.is_a?(String) ? value : text_of(value) }.join("\n")
    else ""
    end
  end
end
