require "test_helper"

class CodeBoxTest < ActiveSupport::TestCase
  setup do
    @box = CodeBox.create!(workspace: workspaces(:slack_workspace_one), key: "investigation-1", provider: SandboxProviders::BOAT, box_ref: "bx_1",
                           **CodeBox.address_columns("https://swift-otter-8080.on.boat.dev?_token=gate"), secret: "key-1",
                           last_used_at: Time.current, box_started_at: 10.minutes.ago, hourly_micros: 36_000)
  end

  test "a token in a box's address is kept encrypted apart from it" do
    assert_equal "https://swift-otter-8080.on.boat.dev", @box.address
    assert_equal "https://swift-otter-8080.on.boat.dev?_token=gate", @box.reload.reach_address
    stored = CodeBox.connection.select_value(CodeBox.where(id: @box.id).select(:address_query).to_sql)
    assert_not_includes stored, "gate"
  end

  test "moving to another box keeps the time the first one ran, and a row stopped meanwhile is left alone" do
    started = Integrations::Sandboxes::Box.new(ref: "bx_2", address: "https://quiet-heron-8080.on.boat.dev?_token=other", key: "key-2")

    assert @box.moved_to!(started, hourly_micros: 36_000)
    assert_equal [ "bx_2", "key-2", "https://quiet-heron-8080.on.boat.dev?_token=other" ], [ @box.box_ref, @box.secret, @box.reach_address ]
    assert_in_delta 600, @box.running_seconds, 2

    travel 5.minutes do
      @box.stop!
    end
    assert_in_delta 900, @box.reload.running_seconds, 2
    assert_not @box.moved_to!(started.with(ref: "bx_3"), hourly_micros: 36_000)
    assert_equal "bx_2", @box.reload.box_ref
  end
end
