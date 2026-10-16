require "test_helper"

class Slack::InstallationMessageBuilderTest < ActiveSupport::TestCase
  test "preview_announcement_blocks says it is only visible to the installer, then shows the announcement card" do
    blocks = Slack::InstallationMessageBuilder.preview_announcement_blocks("U12345678", rich: true)[:blocks]

    assert_includes blocks.first[:elements].first[:text], "Only visible to you"
    card = blocks.second
    assert_equal "card", card[:type]
    assert_includes card.dig(:title, :text), "[PREVIEW] Website is down"
    assert_equal "Minor · Investigating", card.dig(:subtitle, :text)
    assert_includes card.dig(:body, :text), "502 Gateway"
    assert_equal [ Identifiers::PREVIEW_SUBSCRIBE_DISABLED, Identifiers::PREVIEW_HOMEPAGE_DISABLED ], card[:actions].pluck(:action_id)
    assert_equal "Declared by <@U12345678>", blocks.third[:elements].first[:text]
  end

  test "preview_announcement_blocks draws plainly where cards are not drawn, with the same buttons" do
    blocks = Slack::InstallationMessageBuilder.preview_announcement_blocks("U12345678", rich: false)[:blocks]

    assert_not blocks.any? { |block| block[:type] == "card" }
    assert_includes blocks.second.dig(:text, :text), "[PREVIEW] Website is down"
    assert_equal [ Identifiers::PREVIEW_SUBSCRIBE_DISABLED, Identifiers::PREVIEW_HOMEPAGE_DISABLED ],
                 blocks.find { |block| block[:type] == "actions" }[:elements].pluck(:action_id)
  end

  test "share_channel_modal returns valid modal structure" do
    result = Slack::InstallationMessageBuilder.share_channel_modal("U12345678", "C12345678")

    assert_equal "modal", result[:type]
    assert_equal Identifiers::SHARE_INCIDENTS_CHANNEL_MODAL, result[:callback_id]
    assert result[:title].present?
    assert result[:submit].present?
    assert result[:close].present?
    assert result[:blocks].present?
  end

  test "share_channel_modal includes description with user mention" do
    result = Slack::InstallationMessageBuilder.share_channel_modal("U12345678", "C12345678")

    section = result[:blocks].find { |b| b[:type] == "section" }
    assert section.present?
    assert_includes section.dig(:text, :text), "<@U12345678>"
    assert_includes section.dig(:text, :text), "Firefight"
    assert_not_includes section.dig(:text, :text), "FireFight"
  end

  test "share_channel_modal includes channel mention" do
    result = Slack::InstallationMessageBuilder.share_channel_modal("U12345678", "C12345678")

    section = result[:blocks].find { |b| b[:type] == "section" }
    assert section.present?
    assert_includes section.dig(:text, :text), "<#C12345678>"
  end

  test "share_channel_modal includes multi_conversations_select input" do
    result = Slack::InstallationMessageBuilder.share_channel_modal("U12345678", "C12345678")

    input = result[:blocks].find { |b| b[:type] == "input" }
    assert input.present?
    assert_equal "share_target_block", input[:block_id]

    element = input[:element]
    assert_equal "multi_conversations_select", element[:type]
    assert_equal "share_target_select", element[:action_id]
  end

  test "share_message returns valid Block Kit structure" do
    result = Slack::InstallationMessageBuilder.share_message("U12345678", "C12345678", "T12345678")

    assert result[:blocks].present?
    assert result[:blocks].is_a?(Array)
  end

  test "share_message includes user mention" do
    result = Slack::InstallationMessageBuilder.share_message("U12345678", "C12345678", "T12345678")

    section = result[:blocks].find { |b| b[:type] == "section" }
    assert section.present?
    assert_includes section.dig(:text, :text), "<@U12345678>"
  end

  test "share_message includes channel mention" do
    result = Slack::InstallationMessageBuilder.share_message("U12345678", "C12345678", "T12345678")

    section = result[:blocks].find { |b| b[:type] == "section" }
    assert section.present?
    assert_includes section.dig(:text, :text), "<#C12345678>"
  end

  test "share_message includes join button with deep link" do
    result = Slack::InstallationMessageBuilder.share_message("U12345678", "C12345678", "T12345678")

    actions = result[:blocks].find { |b| b[:type] == "actions" }
    assert actions.present?

    button = actions[:elements].first
    assert_equal "button", button[:type]
    assert_equal "primary", button[:style]

    assert_includes button[:url], "slack://channel?team=T12345678"
    assert_includes button[:url], "id=C12345678"
  end

  test "share_message uses correct deep link format" do
    result = Slack::InstallationMessageBuilder.share_message("U99999999", "C88888888", "T77777777")

    actions = result[:blocks].find { |b| b[:type] == "actions" }
    button = actions[:elements].first

    expected_url = "slack://channel?team=T77777777&id=C88888888"
    assert_equal expected_url, button[:url]
  end

  test "all messages use valid block types" do
    messages = [
    Slack::InstallationMessageBuilder.preview_announcement_blocks("U12345678", rich: false),
    Slack::InstallationMessageBuilder.share_message("U12345678", "C12345678", "T12345678")
    ]

    valid_block_types = [ "header", "section", "divider", "actions", "context", "input" ]

    messages.each do |message|
    message[:blocks].each do |block|
      assert_includes valid_block_types, block[:type], "Invalid block type: #{block[:type]}"
      end
    end
  end

  test "all action buttons have required fields" do
    messages = [
    Slack::InstallationMessageBuilder.preview_announcement_blocks("U12345678", rich: false),
    Slack::InstallationMessageBuilder.share_message("U12345678", "C12345678", "T12345678")
    ]

    messages.each do |message|
    actions = message[:blocks].select { |b| b[:type] == "actions" }
    actions.each do |action_block|
      action_block[:elements].each do |button|
        assert button[:type].present?, "Button missing type"
        assert button[:text].present?, "Button missing text"

        # Slack requires a button to carry an action_id or a url.
        assert(button[:action_id].present? || button[:url].present?,
               "Button must have action_id or url")
        end
      end
    end
  end
end
