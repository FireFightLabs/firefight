require "test_helper"

# Subscribers hear what the announcement thread hears, as it was posted.
class IncidentUpdateServiceTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @incident.update!(announcement_message_ts: "1700000000.000100")
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @service = IncidentUpdateService.new(@workspace)
  end

  test "an update reaches the thread and then every subscriber with the same blocks" do
    @incident.subscribe!(@alice)
    @incident.subscribe!(@bob)
    calls = []
    Slack::Client.stubs(:post_message).with { |**kwargs| calls << kwargs }.returns({ ok: true, ts: "1.1", channel: "C1" })

    @service.post_incident_update_announcement_thread(
      @incident, message: "Rolled back", updated_by_platform_user_id: @alice.platform_user_id,
      previous_status_name: "Investigating", previous_severity_name: "Critical"
    )

    thread, *dms = calls
    assert_equal @incident.announcement_message_ts, thread[:thread_ts]
    assert_equal [ @alice.platform_user_id, @bob.platform_user_id ].sort, dms.map { |dm| dm[:channel] }.sort
    dms.each do |dm|
      assert_equal thread[:blocks], dm[:blocks]
      assert_equal thread[:text], dm[:text]
      assert_nil dm[:thread_ts]
    end
  end

  test "a subscriber whose DM fails does not stop the others" do
    @incident.subscribe!(@alice)
    @incident.subscribe!(@bob)
    Slack::Client.stubs(:post_message).returns({ ok: true, ts: "1.1", channel: "C1" })
    Slack::Client.stubs(:post_message).with(has_entries(channel: @alice.platform_user_id)).raises(AdapterError::NotFound, "user_not_found")
    Slack::Client.expects(:post_message).with(has_entries(channel: @bob.platform_user_id)).once.returns({ ok: true, ts: "1.2", channel: @bob.platform_user_id })

    assert_nothing_raised do
      @service.post_resolution_announcement_thread(@incident, resolved_by_platform_user_id: @alice.platform_user_id)
    end
  end

  test "with nobody subscribed only the thread is posted" do
    Slack::Client.expects(:post_message).once.returns({ ok: true, ts: "1.1", channel: "C1" })

    @service.post_reopen_announcement_thread(@incident, reopened_by_platform_user_id: @alice.platform_user_id, reason: "Again")
  end
end
