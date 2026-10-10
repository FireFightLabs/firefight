module Slack
  module Modals
    # Edits a handbook edit or page Halon proposed before accepting it. The page's old wording is kept as history.
    module EditHandbookProposal
      TEXT_BLOCK = "text_block".freeze
      TEXT_INPUT = "text_input".freeze
      # The most a plain text input takes. A longer page is edited on the Handbook page.
      SLACK_INPUT_LIMIT = 3_000

      # proposal is a HandbookProposalService::Shown.
      def self.build(proposal)
        {
          type: "modal",
          callback_id: Identifiers::HANDBOOK_PROPOSAL_EDIT_MODAL,
          private_metadata: ModalState.encode(handbook_proposal_id: proposal.id),
          title: { type: "plain_text", text: "Edit handbook" },
          submit: { type: "plain_text", text: "Accept" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: [
            { type: "section", text: { type: "mrkdwn", text: "*Why Halon proposed it*\n#{Slack::Mrkdwn.escape(proposal.evidence)}" } },
            {
              type: "input",
              block_id: TEXT_BLOCK,
              element: { type: "plain_text_input", action_id: TEXT_INPUT, multiline: true, max_length: SLACK_INPUT_LIMIT,
                         initial_value: proposal.text },
              label: { type: "plain_text", text: proposal.page_title.to_s.truncate(150) },
              hint: { type: "plain_text", text: "Halon follows this from its next chat or investigation. The current wording is kept as history." }
            }
          ]
        }
      end

      def self.text(values) = values.dig(TEXT_BLOCK, TEXT_INPUT, "value").to_s.strip
    end
  end
end
