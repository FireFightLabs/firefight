require "test_helper"

class Slack::Messages::SkillProposalTest < ActiveSupport::TestCase
  Shown = SkillProposalService::Shown
  # Slack refuses a section or context text longer than this.
  SLACK_TEXT_LIMIT = 3_000

  test "the longest proposal a person can write, full of characters Slack escapes, fits every text Slack limits" do
    escaped = "a < b & c > d\n" * 1_500
    proposal = shown(name: "n" * 64, used_when: "<&>" * 166, steps: escaped, reason: "<&>" * 333)

    blocks = Slack::Messages::SkillProposal.build(proposal)

    texts = blocks.flat_map { |block| [ block.dig(:text, :text), *Array(block[:elements]).map { |element| element[:text] if element[:type] == "mrkdwn" } ] }.compact
    texts.each { |text| assert_operator text.length, :<=, SLACK_TEXT_LIMIT }
    steps = blocks.third.dig(:text, :text)
    assert_includes steps, Slack::Messages::SkillProposal::CUT
    assert_no_match(/&[a-z]*\n/, steps, "an entity is never cut in half")
  end

  test "short steps are shown whole, escaped and quoted line by line" do
    blocks = Slack::Messages::SkillProposal.build(shown(steps: "1. Page <@here>\n2. Declare & wait"))

    assert_equal "*game_day*  When a game day starts\n> 1. Page &lt;@here&gt;\n> 2. Declare &amp; wait", blocks.third.dig(:text, :text)
  end

  private

  def shown(name: "game_day", used_when: "When a game day starts", steps: "1. Declare.", reason: "It keeps coming up.")
    Shown.new(id: "proposal-1", name: name, new_skill: true, copy_of: nil, used_when: used_when, tools: [ "declare_incident" ], steps: steps,
              reason: reason, decided: nil, page_url: nil)
  end
end
