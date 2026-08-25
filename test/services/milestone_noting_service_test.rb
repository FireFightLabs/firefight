require "test_helper"

class MilestoneNotingServiceTest < ActiveSupport::TestCase
  include EntitlementsTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @incident.update!(channel_id: "C_MILESTONES")
    @service = MilestoneNotingService.new(@workspace)

    FirefightAi::IncidentSummaryService.any_instance.stubs(:fetch_or_refresh).returns(nil)
    Slack::Client.stubs(:get_permalink).returns({ ok: true, permalink: "https://slack.test/p1" })
  end

  test "writes one note per milestone, quoting the message it came from" do
    add_message(message_id: "1.001", content: "rolling back the 14:02 deploy")
    stub_extraction([ milestone(message_id: "1.001", kind: "mitigation", statement: "Alice rolled back the 14:02 deploy") ])

    events = @service.note!(@incident)

    assert_equal 1, events.size
    event = events.first
    assert_equal IncidentEvent::MILESTONE_NOTED, event.event_type
    assert_nil event.actor
    assert_equal "mitigation", event.metadata["kind"]
    assert_equal "Alice rolled back the 14:02 deploy", event.metadata["statement"]
    assert_equal "rolling back the 14:02 deploy", event.metadata["message_text"]
    assert_equal @member.id, event.metadata["member_id"]
    assert_equal @member.display_name, event.metadata["member_name"]
    assert_equal "https://slack.test/p1", event.metadata["permalink"]
  end

  test "the note sits where the conversation was, not where the pass ran" do
    said_at = 3.hours.ago.change(usec: 0)
    add_message(message_id: "1.001", content: "found it", posted_at: said_at)
    stub_extraction([ milestone(message_id: "1.001") ])

    event = @service.note!(@incident).first

    assert_equal said_at.to_i, event.created_at.to_i
    assert_equal said_at.utc.iso8601, event.metadata["said_at"]
  end

  test "the global switch off means no call and no notes" do
    add_message(message_id: "1.001", content: "anything")
    FirefightAi.configuration.stubs(:milestones_enabled?).returns(false)
    FirefightAi::MilestoneExtractor.any_instance.expects(:extract).never

    assert_empty @service.note!(@incident)
    assert_nil @incident.reload.milestones_noted_through
  end

  test "a workspace without the AI entitlement is never charged for a pass" do
    add_message(message_id: "1.001", content: "anything")
    deny_entitlements!("AI is not included on this plan.")
    FirefightAi::MilestoneExtractor.any_instance.expects(:extract).never

    assert_empty @service.note!(@incident)
  end

  test "an incident with nothing said in it costs nothing" do
    FirefightAi::MilestoneExtractor.any_instance.expects(:extract).never

    assert_empty @service.note!(@incident)
  end

  test "a second pass reads only what was said since the first" do
    add_message(message_id: "1.001", content: "first")
    stub_extraction([ milestone(message_id: "1.001") ])
    @service.note!(@incident)
    assert_equal "1.001", @incident.reload.milestones_noted_through

    add_message(message_id: "1.002", content: "second")
    seen = nil
    FirefightAi::MilestoneExtractor.any_instance.stubs(:extract).with do |_incident, kwargs|
      seen = kwargs[:messages].map(&:message_id)
      true
    end.returns([ milestone(message_id: "1.002") ])

    MilestoneNotingService.new(@workspace).note!(@incident)

    assert_equal [ "1.002" ], seen
    assert_equal "1.002", @incident.reload.milestones_noted_through
  end

  test "a message already noted is never noted twice" do
    add_message(message_id: "1.001", content: "found it")
    stub_extraction([ milestone(message_id: "1.001") ])
    @service.note!(@incident)

    @incident.update!(milestones_noted_through: nil)
    stub_extraction([ milestone(message_id: "1.001") ])

    assert_empty MilestoneNotingService.new(@workspace).note!(@incident)
    assert_equal 1, @incident.incident_events.where(event_type: IncidentEvent::MILESTONE_NOTED).count
  end

  test "two milestones citing the same message yield one note" do
    add_message(message_id: "1.001", content: "found it")
    stub_extraction([
      milestone(message_id: "1.001", statement: "Alice found the lock"),
      milestone(message_id: "1.001", statement: "Alice found the lock again")
    ])

    assert_equal 1, @service.note!(@incident).size
  end

  test "a permalink Slack refuses still leaves the note on the timeline" do
    add_message(message_id: "1.001", content: "found it")
    Slack::Client.stubs(:get_permalink).raises(AdapterError.new("channel_not_found"))
    stub_extraction([ milestone(message_id: "1.001") ])

    event = @service.note!(@incident).first

    assert_not_nil event
    assert_nil event.metadata["permalink"]
    assert_equal "found it", event.metadata["message_text"]
  end

  test "an incident with no channel skips the permalink lookup entirely" do
    @incident.update!(channel_id: nil)
    add_message(message_id: "1.001", content: "found it")
    Slack::Client.expects(:get_permalink).never
    stub_extraction([ milestone(message_id: "1.001") ])

    assert_equal 1, @service.note!(@incident).size
  end

  test "a pass that finds nothing still moves the watermark" do
    add_message(message_id: "1.001", content: "good morning")
    stub_extraction([])

    assert_empty @service.note!(@incident)
    assert_equal "1.001", @incident.reload.milestones_noted_through
  end

  test "dismissed notes are not offered back to the model as already recorded" do
    add_message(message_id: "1.001", content: "found it")
    stub_extraction([ milestone(message_id: "1.001") ])
    note = @service.note!(@incident).first
    note.dismiss!(by: @member)

    add_message(message_id: "1.002", content: "and again")
    seen = nil
    FirefightAi::MilestoneExtractor.any_instance.stubs(:extract).with do |_incident, kwargs|
      seen = kwargs[:timeline]
      true
    end.returns([])

    MilestoneNotingService.new(@workspace).note!(@incident)

    assert_not_includes seen.join(" "), note.metadata["statement"]
  end

  private

  def add_message(message_id:, content:, posted_at: nil)
    @incident.incident_transcript_messages.create!(
      workspace: @workspace,
      workspace_membership: @member,
      message_id: message_id,
      platform_user_id: @member.platform_user_id,
      content: content,
      posted_at: posted_at || Time.at(message_id.to_f)
    )
  end

  def milestone(message_id:, kind: "finding", statement: "Alice confirmed the pool is exhausted", confidence: 0.9)
    FirefightAi::MilestoneExtractor::Milestone.new(
      kind: kind, statement: statement, message_id: message_id, confidence: confidence
    )
  end

  def stub_extraction(milestones)
    FirefightAi::MilestoneExtractor.any_instance.stubs(:extract).returns(milestones)
    FirefightAi::MilestoneExtractor.any_instance.stubs(:last_inference).returns(nil)
  end
end
