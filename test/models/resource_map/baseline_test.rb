require "test_helper"

class ResourceMap::BaselineTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @row = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank").integration_environments.create!
    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [
      ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web")
    ]))
    @web = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "web")
    @to = Time.zone.parse("2026-09-30T05:00:00Z")
  end

  test "normal is the median, the level 95% of readings fall under, and the peak, replaced by each day's read" do
    record(1.upto(100).map { |value| value.to_f })
    baseline = @web.baselines.sole
    assert_equal [ 50.5, 95.05, 100.0, 100 ], [ baseline.typical, baseline.high.round(2), baseline.peak, baseline.points ]
    assert_equal "Requests: usually 51 requests/s, 95% of readings under 95 requests/s, peak 100 requests/s, over the 7 days to 2026-09-30", baseline.line

    record([ 0.4, 0.5, 0.6 ])
    assert_equal [ 0.5, 0.6 ], @web.baselines.sole.values_at(:typical, :peak)
  end

  test "a metric no longer read on a resource that was read goes, and a baseline nobody renews stops being shown" do
    record([ 1.0, 2.0 ])
    record([ 3.0, 4.0 ], metric: "errors")
    assert_equal [ "errors" ], @web.baselines.reload.map(&:metric)

    @web.baselines.update_all(window_to: 3.days.ago)
    assert_empty ResourceMap::Baseline.fresh.where(resource: @web)
  end

  test "a reading with no points, or for a resource not on the map, says nothing about normal" do
    ghost = ResourceMap::Baseline::Found.new(key: [ "northflank", "acme/shop", ResourceMap::KIND_SERVICE, "gone" ], metric: "cpu", label: "CPU", unit: "vCPU", points: [ [ @to, 1.0 ] ])
    empty = ResourceMap::Baseline::Found.new(key: @web.key, metric: "cpu", label: "CPU", unit: "vCPU", points: [])

    assert_equal 0, ResourceMap::Baseline.record!(@row, [ @web ], [ ghost, empty ], window_from: @to - 7.days, window_to: @to)
    assert_empty @web.baselines
  end

  private

  def record(values, metric: "requests")
    points = values.each_with_index.map { |value, index| [ @to - index.minutes, value ] }
    ResourceMap::Baseline.record!(@row, [ @web ], [ ResourceMap::Baseline::Found.new(key: @web.key, metric: metric, label: metric.capitalize, unit: "requests/s", points: points) ],
                                  window_from: @to - 7.days, window_to: @to)
  end
end
