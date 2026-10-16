require "test_helper"

class Operator::PlatformFailuresTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "the reason is the platform's code and its own messages, without the warnings around them" do
    reason = Operator::PlatformFailures.reason(failure!(
      message: 'Slack API error: invalid_arguments (details: {"error":"invalid_arguments","response_metadata":{"messages":' \
               '["[ERROR] missing required field: channel","[ERROR] missing required field: message_ts"],"warnings":["missing_charset"]}})'
    ))

    assert_equal "invalid_arguments", reason.code
    assert_equal [ "missing required field: channel", "missing required field: message_ts" ], reason.notes
    assert_equal "invalid_arguments: missing required field: channel, missing required field: message_ts", reason.line
  end

  test "a code with nothing more to say is the whole reason" do
    reason = Operator::PlatformFailures.reason(failure!(message: 'Slack API error: not_authorized (details: {"error":"not_authorized","response_metadata":{"warnings":["missing_charset"]}})'))

    assert_equal "not_authorized", reason.line
  end

  test "a missing permission names the one it needs" do
    reason = Operator::PlatformFailures.reason(failure!(message: 'Slack API error: missing_scope (details: {"error":"missing_scope","needed":"assistant:write","provided":"chat:write"})'))

    assert_equal "missing_scope: needs assistant:write", reason.line
  end

  test "a message cut short still gives its code and the messages it kept" do
    reason = Operator::PlatformFailures.reason(failure!(message: 'Slack API error: invalid_blocks (details: {"error":"invalid_blocks","response_metadata":{"messages":["[ERROR] must provide an object [json-pointer:/blocks/3/elements/1]","[ERR'))

    assert_equal "invalid_blocks: must provide an object [json-pointer:/blocks/3/elements/1]", reason.line
  end

  test "a failure with no code in its message falls back to its error class" do
    reason = Operator::PlatformFailures.reason(failure!(message: "could not reach the upload address (Net::OpenTimeout)", error_class: "AdapterError::Unavailable"))

    assert_equal "AdapterError::Unavailable", reason.line
  end

  test "the failures like one are those of its workspace, call, code and channel, newest first" do
    first = failure!(message: "Slack API error: not_authorized", channel_id: "C1", created_at: 2.hours.ago)
    latest = failure!(message: "Slack API error: not_authorized", channel_id: "C1")
    failure!(message: "Slack API error: channel_not_found", channel_id: "C1")
    failure!(message: "Slack API error: not_authorized", channel_id: "C2")

    assert_equal [ latest, first ], Operator::PlatformFailures.alike(latest).to_a
  end

  private

  def failure!(message:, error_class: "AdapterError", channel_id: nil, created_at: Time.current)
    PlatformCallFailure.create!(workspace: @workspace, platform: Platforms::SLACK, operation: "chat.getPermalink", error_class: error_class,
                                message: message, channel_id: channel_id, created_at: created_at)
  end
end
