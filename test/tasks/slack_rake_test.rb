require "test_helper"
require "rake"

class SlackArchiveIncidentChannelsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("slack:archive_incident_channels")
    @workspace = workspaces(:slack_workspace_one)
    @resolved_incident = incidents(:resolved_minor_ws1)
    @adapter = mock("workspace_adapter")
    Slack::WorkspaceAdapter.stubs(:new).with { |workspace| workspace.id == @workspace.id }.returns(@adapter)
    Rake::Task["slack:archive_incident_channels"].reenable
    stub_archive_channel
  end

  test "archives closed incident channels" do
    assert_nil @resolved_incident.channel_archived_at

    capture_io do
      Rake::Task["slack:archive_incident_channels"].invoke(@workspace.id)
    end

    @resolved_incident.reload
    assert_not_nil @resolved_incident.channel_archived_at
    assert_equal "rake:slack:archive_incident_channels", @resolved_incident.channel_archived_by
  end

  test "skips incidents that are already archived" do
    @resolved_incident.update!(
      channel_archived_at: 1.day.ago,
      channel_archived_by: "rake:slack:archive_incident_channels"
    )

    Slack::Client.expects(:archive_channel).never

    capture_io do
      Rake::Task["slack:archive_incident_channels"].invoke(@workspace.id)
    end
  end

  test "skips incidents without channel_id" do
    @resolved_incident.update_column(:channel_id, nil)

    Slack::Client.expects(:archive_channel).never

    capture_io do
      Rake::Task["slack:archive_incident_channels"].invoke(@workspace.id)
    end
  end

  test "filters by days when provided" do
    @resolved_incident.update_column(:resolved_at, 3.days.ago)

    capture_io do
      Rake::Task["slack:archive_incident_channels"].invoke(@workspace.id, "5")
    end

    @resolved_incident.reload
    assert_nil @resolved_incident.channel_archived_at
  end

  test "archives incidents older than specified days" do
    @resolved_incident.update_column(:resolved_at, 10.days.ago)

    capture_io do
      Rake::Task["slack:archive_incident_channels"].invoke(@workspace.id, "5")
    end

    @resolved_incident.reload
    assert_not_nil @resolved_incident.channel_archived_at
  end

  test "handles AlreadyArchived gracefully" do
    stub_archive_channel(raises: AdapterError::AlreadyArchived.new("already archived"))

    capture_io do
      Rake::Task["slack:archive_incident_channels"].invoke(@workspace.id)
    end

    @resolved_incident.reload
    assert_not_nil @resolved_incident.channel_archived_at
    assert_equal "rake:slack:archive_incident_channels", @resolved_incident.channel_archived_by
  end

  test "handles API errors without stopping" do
    stub_archive_channel(raises: AdapterError.new("some_error"))

    output, = capture_io do
      Rake::Task["slack:archive_incident_channels"].invoke(@workspace.id)
    end

    @resolved_incident.reload
    assert_nil @resolved_incident.channel_archived_at
    assert_match(/Failed:/, output)
    assert_match(/0 archived, 1 failed/, output)
  end

  test "prints summary with counts" do
    output, = capture_io do
      Rake::Task["slack:archive_incident_channels"].invoke(@workspace.id)
    end

    assert_match(/1 archived, 0 failed/, output)
  end

  test "does not archive active incidents" do
    active_incident = incidents(:active_critical_ws1)
    assert_not active_incident.closed?

    capture_io do
      Rake::Task["slack:archive_incident_channels"].invoke(@workspace.id)
    end

    active_incident.reload
    assert_nil active_incident.channel_archived_at
  end

  private

  def stub_archive_channel(raises: nil)
    if raises
      @adapter.stubs(:archive_channel).raises(raises)
    else
      @adapter.stubs(:archive_channel).returns({ success: true })
    end
  end
end
