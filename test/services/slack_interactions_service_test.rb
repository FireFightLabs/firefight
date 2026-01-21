require "test_helper"

class SlackInteractionsServiceTest < ActiveSupport::TestCase
  setup do
    @service = SlackInteractionsService.new
    @workspace = Workspace.create!(
      platform: "slack",
      platform_id: "T#{SecureRandom.hex(8)}",
      name: "Test Workspace",
      access_token: "xoxb-test-token",
      installed_at: Time.current,
      incidents_channel_id: "C12345678"
    )
  end

  # handle_preview_announcement tests

  test "handle_preview_announcement posts ephemeral preview message" do
    payload = mock_slack_interaction_payload(
      team_id: @workspace.platform_id,
      type: "block_actions",
      overrides: {
        "actions" => [ { "action_id" => "preview_announcement" } ]
      }
    )

    stub_post_ephemeral do
      result = @service.handle_preview_announcement(payload)

      assert_equal "clear", result[:response_action]
    end
  end

  test "handle_preview_announcement logs event" do
    payload = mock_slack_interaction_payload(team_id: @workspace.platform_id, type: "block_actions")
    logged_events = []
    original_logger = Rails.logger

    Rails.logger = Logger.new(IO::NULL)
    Rails.logger.define_singleton_method(:info) do |message|
      logged_events << message if message.is_a?(Hash)
    end

    stub_post_ephemeral do
      @service.handle_preview_announcement(payload)
    end

    event = logged_events.find { |e| e[:event] == "interactions.preview_posted" }
    assert event.present?
    assert_equal @workspace.id, event[:workspace_id]
    assert_equal "U12345678", event[:user_id]

    Rails.logger = original_logger
  end

  test "handle_preview_announcement raises error if workspace not found" do
    payload = mock_slack_interaction_payload(
      team_id: @workspace.platform_id,
      type: "block_actions",
      overrides: { "team" => { "id" => "T_NONEXISTENT" } }
    )

    assert_raises(ActiveRecord::RecordNotFound) do
      @service.handle_preview_announcement(payload)
    end
  end

  # handle_share_channel tests

  test "handle_share_channel opens modal successfully" do
    payload = mock_slack_interaction_payload(
      team_id: @workspace.platform_id,
      type: "block_actions",
      overrides: {
        "actions" => [ { "action_id" => "share_incidents_channel" } ]
      }
    )

    stub_open_modal do
      result = @service.handle_share_channel(payload)

      assert_equal "clear", result[:response_action]
    end
  end

  test "handle_share_channel handles expired trigger" do
    payload = mock_slack_interaction_payload(team_id: @workspace.platform_id, type: "block_actions")

    stub_open_modal(raises: Slack::Client::TriggerExpiredError.new("Trigger expired")) do
      result = @service.handle_share_channel(payload)

      assert_equal "errors", result[:response_action]
      assert result[:errors][:base].present?
      assert_includes result[:errors][:base], "expired"
    end
  end

  test "handle_share_channel logs modal opened event" do
    payload = mock_slack_interaction_payload(team_id: @workspace.platform_id, type: "block_actions")
    logged_events = []
    original_logger = Rails.logger

    Rails.logger = Logger.new(IO::NULL)
    Rails.logger.define_singleton_method(:info) do |message|
      logged_events << message if message.is_a?(Hash)
    end

    stub_open_modal do
      @service.handle_share_channel(payload)
    end

    event = logged_events.find { |e| e[:event] == "interactions.share_modal_opened" }
    assert event.present?
    assert_equal @workspace.id, event[:workspace_id]

    Rails.logger = original_logger
  end

  test "handle_share_channel logs warning on trigger expired" do
    payload = mock_slack_interaction_payload(team_id: @workspace.platform_id, type: "block_actions")
    logged_events = []
    original_logger = Rails.logger

    Rails.logger = Logger.new(IO::NULL)
    Rails.logger.define_singleton_method(:warn) do |message|
      logged_events << message if message.is_a?(Hash)
    end

    stub_open_modal(raises: Slack::Client::TriggerExpiredError.new("Trigger expired")) do
      @service.handle_share_channel(payload)
    end

    event = logged_events.find { |e| e[:event] == "interactions.trigger_expired" }
    assert event.present?

    Rails.logger = original_logger
  end

  # handle_share_modal_submission tests

  test "handle_share_modal_submission shares to selected channels" do
    payload = mock_slack_interaction_payload(team_id: @workspace.platform_id, type: "view_submission")

    stub_post_message do
      result = @service.handle_share_modal_submission(payload)

      assert_equal "clear", result[:response_action]
    end
  end

  test "handle_share_modal_submission returns error if no targets selected" do
    payload = mock_slack_interaction_payload(
      team_id: @workspace.platform_id,
      type: "view_submission",
      overrides: {
        "view" => {
          "callback_id" => "share_incidents_channel_modal",
          "state" => {
            "values" => {
              "share_target_block" => {
                "share_target_select" => {
                  "selected_conversations" => []
                }
              }
            }
          }
        }
      }
    )

    result = @service.handle_share_modal_submission(payload)

    assert_equal "errors", result[:response_action]
    assert result[:errors][:share_target_block].present?
    assert_includes result[:errors][:share_target_block], "at least one"
  end

  test "handle_share_modal_submission logs warning if no targets selected" do
    payload = mock_slack_interaction_payload(
      team_id: @workspace.platform_id,
      type: "view_submission",
      overrides: {
        "view" => {
          "callback_id" => "share_incidents_channel_modal",
          "state" => {
            "values" => {
              "share_target_block" => {
                "share_target_select" => {
                  "selected_conversations" => []
                }
              }
            }
          }
        }
      }
    )

    logged_events = []
    original_logger = Rails.logger

    Rails.logger = Logger.new(IO::NULL)
    Rails.logger.define_singleton_method(:warn) do |message|
      logged_events << message if message.is_a?(Hash)
    end

    @service.handle_share_modal_submission(payload)

    event = logged_events.find { |e| e[:event] == "interactions.share_no_targets" }
    assert event.present?

    Rails.logger = original_logger
  end

  test "handle_share_modal_submission logs success event" do
    payload = mock_slack_interaction_payload(team_id: @workspace.platform_id, type: "view_submission")
    logged_events = []
    original_logger = Rails.logger

    Rails.logger = Logger.new(IO::NULL)
    Rails.logger.define_singleton_method(:info) do |message|
      logged_events << message if message.is_a?(Hash)
    end

    stub_post_message do
      @service.handle_share_modal_submission(payload)
    end

    event = logged_events.find { |e| e[:event] == "interactions.channel_shared" }
    assert event.present?
    assert_equal 1, event[:target_count]
    assert_equal [ "C87654321" ], event[:targets]

    Rails.logger = original_logger
  end

  test "handle_share_modal_submission handles multiple targets" do
    payload = mock_slack_interaction_payload(
      team_id: @workspace.platform_id,
      type: "view_submission",
      overrides: {
        "view" => {
          "callback_id" => "share_incidents_channel_modal",
          "state" => {
            "values" => {
              "share_target_block" => {
                "share_target_select" => {
                  "selected_conversations" => [ "C11111111", "C22222222", "D33333333" ]
                }
              }
            }
          }
        }
      }
    )

    post_count = 0
    original_post = Slack::Client.method(:post_message)
    Slack::Client.define_singleton_method(:post_message) do |**args|
      post_count += 1
      { ok: true, ts: "123.#{post_count}" }
    end

    @service.handle_share_modal_submission(payload)

    # Should have attempted to post to 3 targets
    assert_equal 3, post_count

    Slack::Client.define_singleton_method(:post_message, original_post)
  end

  # find_workspace tests

  test "find_workspace extracts team_id from team field" do
    payload = mock_slack_interaction_payload(team_id: @workspace.platform_id, type: "block_actions")

    stub_post_ephemeral do
      result = @service.handle_preview_announcement(payload)
      assert result.present?
    end
  end

  test "find_workspace extracts team_id from user.team_id field" do
    payload = mock_slack_interaction_payload(
      team_id: @workspace.platform_id,
      type: "block_actions",
      overrides: {
        "team" => nil,
        "user" => { "id" => "U12345678", "team_id" => @workspace.platform_id }
      }
    )

    stub_post_ephemeral do
      result = @service.handle_preview_announcement(payload)
      assert result.present?
    end
  end

  test "find_workspace raises error if team_id not found in payload" do
    payload = mock_slack_interaction_payload(
      team_id: "T_NONEXISTENT",
      type: "block_actions",
      overrides: {
        "team" => { "id" => "T_NONEXISTENT" },
        "user" => { "id" => "U12345678", "team_id" => "T_NONEXISTENT" }
      }
    )

    assert_raises(ActiveRecord::RecordNotFound) do
      @service.handle_preview_announcement(payload)
    end
  end
end
