require "test_helper"

class DashboardStatsTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages, :incident_statuses, :incident_severities, :incidents

  test "to_a returns four stat hashes" do
    stats = DashboardStats.new(workspaces(:slack_workspace_one)).to_a

    assert_equal 4, stats.length
    assert_equal "Active Incidents", stats[0][:label]
    assert_equal "Avg. Resolution Time", stats[1][:label]
    assert_equal "Total Incidents", stats[2][:label]
    assert_equal "Critical Incidents", stats[3][:label]
  end

  test "active incidents counts live incidents" do
    workspace = workspaces(:slack_workspace_one)
    stats = DashboardStats.new(workspace).to_a

    expected_count = workspace.incidents.active.where(deleted_at: nil).count
    assert_equal expected_count.to_s, stats[0][:value]
  end

  test "mttr returns N/A when no incidents have been resolved" do
    workspace = Workspace.create!(
      platform: "slack", platform_id: "T#{SecureRandom.hex(8)}",
      name: "Empty Workspace", access_token: "xoxb-test", installed_at: Time.current
    )

    stats = DashboardStats.new(workspace).to_a
    assert_equal "—", stats[1][:value]
  end

  test "mttr computes average for all resolved incidents" do
    workspace = workspaces(:slack_workspace_one)
    Rails.cache.delete("dashboard_stats/#{workspace.id}/mttr")
    stats = DashboardStats.new(workspace).to_a

    resolved = workspace.incidents
      .where(deleted_at: nil)
      .where.not(resolved_at: nil)

    if resolved.any?
      avg_minutes = resolved.pluck(:declared_at, :resolved_at)
        .map { |d, r| ((r - d) / 60.0).round }
        .then { |times| times.sum / times.size }
      expected = DashboardStats.new(workspace).send(:format_minutes, avg_minutes)
      assert_equal expected, stats[1][:value]
    else
      assert_equal "—", stats[1][:value]
    end
  end

  test "format_minutes returns short duration strings" do
    stats = DashboardStats.new(workspaces(:slack_workspace_one))
    assert_equal "45m", stats.send(:format_minutes, 45)
    assert_equal "1h", stats.send(:format_minutes, 60)
    assert_equal "1h 35m", stats.send(:format_minutes, 95)
    assert_equal "1d", stats.send(:format_minutes, 1440)
    assert_equal "1d 21h", stats.send(:format_minutes, 2753)
  end

  test "critical incidents returns 0 when no critical severity exists" do
    workspace = workspaces(:slack_workspace_two)
    stats = DashboardStats.new(workspace).to_a

    assert_equal "0", stats[3][:value]
  end

  test "each stat hash has required keys" do
    stats = DashboardStats.new(workspaces(:slack_workspace_one)).to_a

    stats.each do |stat|
      assert stat.key?(:label), "Missing :label"
      assert stat.key?(:value), "Missing :value"
      assert stat.key?(:trendDescription), "Missing :trendDescription"
      assert stat.key?(:detail), "Missing :detail"
    end
  end
end
