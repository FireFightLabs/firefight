require "test_helper"

class Slack::InstallationMessageBuilderTest < ActiveSupport::TestCase
  # welcome_message_blocks tests

  test "welcome_message_blocks returns valid Block Kit structure" do
    result = Slack::InstallationMessageBuilder.welcome_message_blocks

    assert result[:blocks].present?
    assert result[:blocks].is_a?(Array)
    assert result[:blocks].length > 0
  end

  test "welcome_message_blocks includes header block" do
    result = Slack::InstallationMessageBuilder.welcome_message_blocks

    header = result[:blocks].find { |b| b[:type] == "header" }
    assert header.present?
    assert_equal "Welcome to FireFight!", header.dig(:text, :text)
  end

  test "welcome_message_blocks includes description section" do
    result = Slack::InstallationMessageBuilder.welcome_message_blocks

    sections = result[:blocks].select { |b| b[:type] == "section" }
    assert sections.any? { |s| s.dig(:text, :text)&.include?("central incident hub") }
  end

  test "welcome_message_blocks includes action buttons" do
    result = Slack::InstallationMessageBuilder.welcome_message_blocks

    actions = result[:blocks].find { |b| b[:type] == "actions" }
    assert actions.present?
    assert_equal 2, actions[:elements].length

    # Share button
    share_button = actions[:elements].find { |e| e[:action_id] == "share_incidents_channel" }
    assert share_button.present?
    assert_equal "button", share_button[:type]
    assert_equal "primary", share_button[:style]

    # Preview button
    preview_button = actions[:elements].find { |e| e[:action_id] == "preview_announcement" }
    assert preview_button.present?
    assert_equal "button", preview_button[:type]
  end

  # preview_announcement_blocks tests

  test "preview_announcement_blocks returns valid Block Kit structure" do
    result = Slack::InstallationMessageBuilder.preview_announcement_blocks("U12345678")

    assert result[:blocks].present?
    assert result[:blocks].is_a?(Array)
    assert result[:blocks].length > 0
  end

  test "preview_announcement_blocks includes context indicating ephemeral" do
    result = Slack::InstallationMessageBuilder.preview_announcement_blocks("U12345678")

    context = result[:blocks].find { |b| b[:type] == "context" }
    assert context.present?
    assert context[:elements].any? { |e| e[:text]&.include?("Only visible to you") }
  end

  test "preview_announcement_blocks includes incident header" do
    result = Slack::InstallationMessageBuilder.preview_announcement_blocks("U12345678")

    header = result[:blocks].find { |b| b[:type] == "header" }
    assert header.present?
    assert_includes header.dig(:text, :text), "[PREVIEW]"
    assert_includes header.dig(:text, :text), "Website is down"
  end

  test "preview_announcement_blocks includes incident description" do
    result = Slack::InstallationMessageBuilder.preview_announcement_blocks("U12345678")

    sections = result[:blocks].select { |b| b[:type] == "section" }
    description = sections.find { |s| s.dig(:text, :text)&.include?("502 Gateway") }
    assert description.present?
  end

  test "preview_announcement_blocks includes severity field" do
    result = Slack::InstallationMessageBuilder.preview_announcement_blocks("U12345678")

    sections = result[:blocks].select { |b| b[:type] == "section" }
    severity = sections.find { |s| s.dig(:text, :text)&.include?("Severity") }
    assert severity.present?
    assert_includes severity.dig(:text, :text), "Minor"
  end

  test "preview_announcement_blocks includes status field" do
    result = Slack::InstallationMessageBuilder.preview_announcement_blocks("U12345678")

    sections = result[:blocks].select { |b| b[:type] == "section" }
    status = sections.find { |s| s.dig(:text, :text)&.include?("Status") }
    assert status.present?
    assert_includes status.dig(:text, :text), "Investigating"
  end

  test "preview_announcement_blocks includes reporter field with user mention" do
    result = Slack::InstallationMessageBuilder.preview_announcement_blocks("U12345678")

    sections = result[:blocks].select { |b| b[:type] == "section" }
    reporter = sections.find { |s| s.dig(:text, :text)&.include?("Reporter") }
    assert reporter.present?
    assert_includes reporter.dig(:text, :text), "<@U12345678>"
  end

  test "preview_announcement_blocks includes incident lead with firefighter emoji" do
    result = Slack::InstallationMessageBuilder.preview_announcement_blocks("U12345678")

    sections = result[:blocks].select { |b| b[:type] == "section" }
    lead = sections.find { |s| s.dig(:text, :text)&.include?("Incident Lead") }
    assert lead.present?
    assert_includes lead.dig(:text, :text), ":firefighter:"
    assert_includes lead.dig(:text, :text), "<@U12345678>"
  end

  test "preview_announcement_blocks includes dividers" do
    result = Slack::InstallationMessageBuilder.preview_announcement_blocks("U12345678")

    dividers = result[:blocks].select { |b| b[:type] == "divider" }
    assert dividers.length >= 2, "Should have at least 2 dividers"
  end

  test "preview_announcement_blocks includes action buttons" do
    result = Slack::InstallationMessageBuilder.preview_announcement_blocks("U12345678")

    actions = result[:blocks].find { |b| b[:type] == "actions" }
    assert actions.present?
    assert_equal 2, actions[:elements].length

    # Homepage button
    homepage_button = actions[:elements].find { |e| e[:action_id] == "preview_homepage_disabled" }
    assert homepage_button.present?
    assert_equal "primary", homepage_button[:style]

    # Subscribe button
    subscribe_button = actions[:elements].find { |e| e[:action_id] == "preview_subscribe_disabled" }
    assert subscribe_button.present?
  end

  test "preview_announcement_blocks uses vertical layout not grid" do
    result = Slack::InstallationMessageBuilder.preview_announcement_blocks("U12345678")

    # Verify no section has "fields" array (which creates grid layout)
    sections = result[:blocks].select { |b| b[:type] == "section" }
    sections.each do |section|
      assert_nil section[:fields], "Sections should not use fields array (grid layout)"
    end
  end

  # share_channel_modal tests

  test "share_channel_modal returns valid modal structure" do
    result = Slack::InstallationMessageBuilder.share_channel_modal("U12345678", "C12345678")

    assert_equal "modal", result[:type]
    assert_equal "share_incidents_channel_modal", result[:callback_id]
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
    assert_includes section.dig(:text, :text), "FireFight"
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

  # share_message tests

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

    # Verify deep link format includes team_id
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

  # Slack Block Kit validation

  test "all messages use valid block types" do
    messages = [
      Slack::InstallationMessageBuilder.welcome_message_blocks,
      Slack::InstallationMessageBuilder.preview_announcement_blocks("U12345678"),
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
      Slack::InstallationMessageBuilder.welcome_message_blocks,
      Slack::InstallationMessageBuilder.preview_announcement_blocks("U12345678"),
      Slack::InstallationMessageBuilder.share_message("U12345678", "C12345678", "T12345678")
    ]

    messages.each do |message|
      actions = message[:blocks].select { |b| b[:type] == "actions" }
      actions.each do |action_block|
        action_block[:elements].each do |button|
          assert button[:type].present?, "Button missing type"
          assert button[:text].present?, "Button missing text"

          # Buttons must have either action_id or url
          assert(button[:action_id].present? || button[:url].present?,
                 "Button must have action_id or url")
        end
      end
    end
  end
end
