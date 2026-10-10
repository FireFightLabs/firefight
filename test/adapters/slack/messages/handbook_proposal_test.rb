require "test_helper"

class Slack::Messages::HandbookProposalTest < ActiveSupport::TestCase
  Shown = HandbookProposalService::Shown

  test "a waiting proposal shows the page, the wording, what the handbook says now and why, with Accept, Edit and Dismiss" do
    blocks = Slack::Messages::HandbookProposal.build(shown(decided: nil))

    assert_equal ":ledger:  *Halon proposes a handbook edit*", blocks.first.dig(:text, :text)
    assert_equal "divider", blocks.second[:type]
    assert_equal "*How we release*\n> Run the deploy workflow\n> then check checkout", blocks.third.dig(:text, :text)
    assert_includes text_of(blocks), "*The handbook says now*\n> Run the release pipeline"
    assert_includes text_of(blocks), "Why: The last five releases ran through the deploy workflow."
    actions = blocks.find { |block| block[:type] == "actions" }[:elements]
    assert_equal [ "Accept", "Edit", "Dismiss" ], actions.map { |button| button.dig(:text, :text) }
    assert_equal [ Identifiers::HANDBOOK_PROPOSAL_ACCEPT, Identifiers::HANDBOOK_PROPOSAL_EDIT, Identifiers::HANDBOOK_PROPOSAL_DISMISS ], actions.map { |button| button[:action_id] }
    assert(actions.all? { |button| button[:value] == "proposal-1" })
  end

  test "a decided proposal says who decided and carries no buttons" do
    blocks = Slack::Messages::HandbookProposal.build(shown(decided: "Accepted by Ana."))

    assert_nil(blocks.find { |block| block[:type] == "actions" })
    assert_includes text_of(blocks), "Accepted by Ana."
    assert_not_includes text_of(blocks), "The handbook says now"
  end

  test "model and person text is escaped" do
    blocks = Slack::Messages::HandbookProposal.build(shown(decided: nil, text: "Ping <!channel> & <@U1>"))

    assert_includes text_of(blocks), "Ping &lt;!channel&gt; &amp; &lt;@U1&gt;"
  end

  private

  def shown(decided:, text: "Run the deploy workflow\nthen check checkout")
    Shown.new(id: "proposal-1", page_title: "How we release", new_page: false, current_wording: "Run the release pipeline", text: text,
              evidence: "The last five releases ran through the deploy workflow.", decided: decided)
  end

  def text_of(blocks) = blocks.to_json.then { |json| JSON.parse(json) }.flat_map { |block| [ block.dig("text", "text"), *Array(block["elements"]).map { |element| element["text"].is_a?(String) ? element["text"] : nil } ] }.compact.join("\n")
end
