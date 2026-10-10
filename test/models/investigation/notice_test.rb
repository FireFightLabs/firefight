require "test_helper"

class Investigation::NoticeTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @disk = ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_DATABASE,
                                          external_id: "orders-db", name: "orders-db", first_seen_at: Time.current, last_seen_at: Time.current)
  end

  def reading(severity: Investigation::Notice::SEVERITY_MEDIUM, due_on: Date.new(2026, 10, 28), resource: @disk)
    Investigation::Notice::Reading.new(signal: Investigation::Notice::SIGNAL_DISK, topic: "orders-db volume",
                                       summary: "The orders-db volume is 81% full and grows about 1.2% a day, so it is full around Oct 28.",
                                       severity: severity, due_on: due_on, resource: resource)
  end

  def said(notice) = notice.said!(channel_id: "C1", message_id: "1.1")

  test "a problem is news the first time, and the same reading again is not" do
    travel_to Time.utc(2026, 10, 10) do
      first = Investigation::Notice.observe!(@workspace, reading)
      assert first
      assert first.unsaid
      said(first)

      assert_nil Investigation::Notice.observe!(@workspace, reading)
      assert_not first.reload.unsaid
      assert_equal 1, @workspace.investigation_notices.count
    end
  end

  test "it is said again when it is more urgent" do
    travel_to(Time.utc(2026, 10, 10)) { said(Investigation::Notice.observe!(@workspace, reading)) }

    travel_to Time.utc(2026, 10, 11) do
      assert Investigation::Notice.observe!(@workspace, reading(severity: Investigation::Notice::SEVERITY_HIGH))
    end
  end

  test "a date that wobbles by a day is not news, one that moved a quarter of the time left is" do
    travel_to(Time.utc(2026, 10, 10)) { said(Investigation::Notice.observe!(@workspace, reading)) }

    travel_to Time.utc(2026, 10, 11) do
      assert_nil Investigation::Notice.observe!(@workspace, reading(due_on: Date.new(2026, 10, 27)))
      assert Investigation::Notice.observe!(@workspace, reading(due_on: Date.new(2026, 10, 22)))
    end
  end

  test "two runs that read the same problem at once both find it news, and only one of them gets to say it" do
    travel_to Time.utc(2026, 10, 10) do
      first = Investigation::Notice.observe!(@workspace, reading)
      second = Investigation::Notice.observe!(@workspace, reading)

      assert first
      assert second
      assert first.claim!
      assert_not second.claim!
      assert_equal 1, @workspace.investigation_notices.count
    end
  end

  test "deciding news is one statement, so a copy read before another run said it cannot say it again" do
    travel_to(Time.utc(2026, 10, 10)) { Investigation::Notice.observe!(@workspace, reading) }
    stale = @workspace.investigation_notices.sole
    fresh = Investigation::Notice.find(stale.id)
    assert fresh.claim!
    fresh.said!(channel_id: "C1", message_id: "1.1")

    travel_to Time.utc(2026, 10, 11) do
      assert_nil Investigation::Notice.observe!(@workspace, reading)
      assert_not stale.claim!
    end
  end

  test "a problem not seen for weeks that comes back is news again" do
    travel_to(Time.utc(2026, 9, 1)) { said(Investigation::Notice.observe!(@workspace, reading)) }

    travel_to(Time.utc(2026, 10, 10)) { assert Investigation::Notice.observe!(@workspace, reading) }
  end

  test "one not said yet stays news until it is" do
    travel_to(Time.utc(2026, 10, 10)) { Investigation::Notice.observe!(@workspace, reading) }

    travel_to(Time.utc(2026, 10, 11)) { assert Investigation::Notice.observe!(@workspace, reading) }
  end

  test "it goes to the channel of the team that owns what it is about, else the workspace's monitoring channel" do
    team = catalog_entries(:platform_team)
    team.update!(attributes: team.entry_attributes.merge("slack_channel" => "C_PLATFORM"))
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:auth_service), resource: @disk)
    @workspace.update!(halon_monitoring_channel: "C_MONITORING")

    assert_equal "C_PLATFORM", Investigation::Notice.channel_for(@workspace, @disk.reload)
    assert_equal "C_MONITORING", Investigation::Notice.channel_for(@workspace, nil)
  end

  test "a service's own channel comes before its team's" do
    service = catalog_entries(:auth_service)
    service.update!(attributes: service.entry_attributes.merge("slack_channel" => "C_AUTH"))
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: service, resource: @disk)

    assert_equal "C_AUTH", Investigation::Notice.channel_for(@workspace, @disk.reload)
  end

  test "with no owner and no monitoring channel there is nowhere to say it" do
    assert_nil Investigation::Notice.channel_for(@workspace, @disk)
  end

  test "an alert keeps its own key, so two alerts in one repository are two problems" do
    one = Investigation::Notice::Reading.new(signal: Investigation::Notice::SIGNAL_LEAKED_SECRET, topic: "a", summary: "a",
                                             severity: Investigation::Notice::SEVERITY_MEDIUM, resource: @disk, reference: "github:acme/api#1")
    two = one.with(reference: "github:acme/api#2")

    assert_not_equal one.key, two.key
  end
end
