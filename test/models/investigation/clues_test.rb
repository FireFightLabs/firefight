require "test_helper"

class Investigation::CluesTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @investigation = @incident.investigations.live.first || @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    @source = @workspace.alert_sources.create!(name: "Datadog", provider: AlertSource::PROVIDER_GENERIC)
  end

  test "an alert's commit, service, first seen time, stack frames and error name all become clues with their source" do
    @incident.update_columns(declared_at: Time.utc(2026, 9, 24, 14, 10), detected_at: nil)
    alert!(
      received_at: Time.utc(2026, 9, 24, 14, 5),
      fields: {
        "title" => "PoolExhausted: could not obtain a connection",
        "tags" => { "service" => "checkout", "git.commit.sha" => "a1b2c3d4e5f6" },
        "first_seen" => "2026-09-24T13:40:00Z",
        "stack" => "at Pool.checkout (/app/app/models/pool.rb:42)\\nat vendor/bundle/gems/pg/lib/pg.rb:10"
      }
    )

    clues = Investigation::Clues.new(@investigation).gather

    assert_equal "2026-09-24T13:40:00Z", clues["started"]["at"], "the earliest sign wins over when the alert arrived"
    assert_match "first_seen", clues["started"]["source"]
    assert_equal [ "a1b2c3d4e5f6" ], clues["commits"].map { |clue| clue["value"] }
    assert_includes clues["names"].map { |clue| clue["value"] }, "checkout"
    assert_equal [ [ "app/app/models/pool.rb", 42 ] ], clues["paths"].map { |clue| [ clue["value"], clue["line"] ] },
                 "a frame inside a dependency says where it broke, not whose code broke it"
    assert_includes clues["error_texts"].map { |clue| clue["value"] }, "PoolExhausted"
    assert_match "alert from Datadog", clues["names"].first["source"]
  end

  test "what the run was told is a clue too, and a start from it is not an estimate" do
    @investigation.update!(brief: Investigation::Brief.from(
      { "started_around" => "2026-09-24T12:00:00Z", "names" => [ "payments" ], "error_text" => "timeout calling Stripe" },
      source: Investigation::Brief::SOURCE_CHAT
    ))

    clues = Investigation::Clues.new(@investigation).gather

    assert_includes clues["names"].map { |clue| clue["value"] }, "payments"
    assert_includes clues["error_texts"].map { |clue| clue["value"] }, "timeout calling Stripe"
    assert_not clues["started"]["estimated"]
  end

  test "with no alert and nothing said, the start is the incident's own time and marked an estimate" do
    clues = Investigation::Clues.new(@investigation).gather

    assert clues["started"]["estimated"]
    assert_match "incident", clues["started"]["source"]
  end

  private

  def alert!(received_at:, fields:)
    @source.alerts.create!(
      workspace: @workspace, incident: @incident, external_id: SecureRandom.hex(4), fingerprint: SecureRandom.hex(4),
      status: Alert::STATUS_FIRING, received_at: received_at, last_seen_at: received_at, fields: fields
    )
  end
end
