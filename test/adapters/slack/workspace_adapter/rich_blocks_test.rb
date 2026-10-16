require "test_helper"

class Slack::WorkspaceAdapter::RichBlocksTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @adapter = Slack::WorkspaceAdapter.new(@workspace)
  end

  test "an announcement goes as a card where Slack draws one" do
    Slack::Client.expects(:post_message).with { |blocks:, **| blocks.first[:type] == "card" }.returns({ ok: true, ts: "1.1", channel: "C1" })

    @adapter.post_incident_announcement(channel_id: "C1", incident: @incident)
  end

  test "a refused card is posted plain at once, remembered for cards alone, and tried again after a week" do
    posted = []
    Slack::Client.stubs(:post_message).with do |blocks:, **|
      posted << blocks.first[:type]
      raise AdapterError::Unrenderable, "invalid_blocks" if blocks.first[:type] == "card"

      true
    end.returns({ ok: true, ts: "1.1", channel: "C1" })

    @adapter.post_incident_announcement(channel_id: "C1", incident: @incident)
    @adapter.post_incident_announcement(channel_id: "C1", incident: @incident)

    assert_equal %w[card section section], posted
    assert @workspace.reload.platform_data["card_blocks_refused_at"].present?
    assert_nil @workspace.platform_data["alert_blocks_refused_at"], "a refused card never takes alerts with it"

    travel 8.days do
      posted.clear
      Slack::WorkspaceAdapter.new(@workspace.reload).post_incident_announcement(channel_id: "C1", incident: @incident)
      assert_equal "card", posted.first
    end
  end

  test "a refused alert falls back to the bold title, and the resolution still posts" do
    Slack::Client.stubs(:post_message).with { |blocks:, **| blocks.first[:type] == "alert" }.raises(AdapterError::Unrenderable, "invalid_blocks")
    Slack::Client.expects(:post_message).with { |blocks:, **| blocks.first[:type] == "section" && blocks.first.dig(:text, :text).include?("Resolved by") }
                 .returns({ ok: true, ts: "1.1", channel: "C1" })

    @adapter.post_resolution_message(channel_id: "C1", incident: @incident, resolved_by_platform_user_id: "U1")

    assert @workspace.reload.platform_data["alert_blocks_refused_at"].present?
  end

  test "a long reply is never cut: it runs on into sections and messages, and every word arrives" do
    words = Array.new(40_000) { |index| "w#{index}" }
    text = words.each_slice(20).map { |slice| slice.join(" ") }.join("\n")
    posted = []
    Slack::Client.stubs(:post_message).with { |**arguments| posted << arguments }.returns({ ok: true, ts: "1.5" })
    Slack::Client.stubs(:set_agent_session_status).returns({ ok: true })

    @adapter.post_agent_reply(channel_id: "C1", thread_id: "1.2", answer_id: nil, text: text)

    assert_operator posted.size, :>, 1
    assert posted.all? { |arguments| arguments[:thread_ts] == "1.2" && arguments[:blocks].size <= 50 }
    sections = posted.flat_map { |arguments| arguments[:blocks] }.map { |block| block.dig(:text, :text) }
    assert sections.all? { |section| section.length <= Slack::Messages::Formatting::SECTION_TEXT_LIMIT }
    assert_equal words, sections.join("\n").split(/\s+/)
  end

  test "a reply's markdown links render as Slack links" do
    Slack::Client.expects(:post_message).with { |blocks:, **| blocks.sole.dig(:text, :text) == "Opened <https://github.com/acme/app/pull/856|PR #856>." }
                 .returns({ ok: true, ts: "1.5" })
    Slack::Client.stubs(:set_agent_session_status).returns({ ok: true })

    @adapter.post_agent_reply(channel_id: "C1", thread_id: "1.2", answer_id: nil, text: "Opened [PR #856](https://github.com/acme/app/pull/856).")
  end

  test "catchup answers are signed by Halon, never Firefight AI" do
    blocks = Slack::Messages::AiResponse.build(incident: @incident, answer: "All good")

    assert_equal "Answered by Halon", blocks.last.dig(:elements, 0, :text)
    assert_not blocks.to_s.include?("Firefight AI")
  end
end
