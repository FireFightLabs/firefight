module Slack
  module Messages
    # A handbook edit Halon proposed because something it read contradicted the handbook, or a new page it drafted, with
    # Accept, Edit and Dismiss while it waits, and who decided once someone did. A page longer than Slack shows is cut,
    # and one longer than its form takes is edited on the Handbook page.
    module HandbookProposal
      TITLE = ":ledger:  *Halon proposes a handbook edit*".freeze
      NEW_PAGE_TITLE = ":ledger:  *Halon proposes a handbook page*".freeze
      FOOTER = "Nothing in the handbook changes until someone accepts this.".freeze
      # A section's text holds at most 3,000 characters, with room left for the heading.
      SHOWN = 2_500
      CUT = "_Cut short here. The Handbook page shows it whole._".freeze

      # proposal is a HandbookProposalService::Shown.
      def self.build(proposal)
        [
          { type: "section", text: { type: "mrkdwn", text: proposal.new_page ? NEW_PAGE_TITLE : TITLE } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: "*#{Slack::Mrkdwn.escape(proposal.page_title)}*\n#{quoted(proposal.text)}" } },
          (now(proposal) if proposal.decided.nil? && !proposal.new_page),
          { type: "context", elements: [ { type: "mrkdwn", text: "Why: #{Slack::Mrkdwn.escape(proposal.evidence.to_s.truncate(SHOWN))}" } ] },
          (proposal.decided ? decided(proposal) : actions(proposal)),
          ({ type: "context", elements: [ { type: "mrkdwn", text: FOOTER } ] } if proposal.decided.nil?)
        ].compact
      end

      def self.fallback(proposal)
        "Halon proposes #{proposal.new_page ? 'a handbook page' : 'a handbook edit to'} #{proposal.page_title}: #{proposal.text.to_s.truncate(SHOWN)}"
      end

      # Model and person text, so it is escaped and quoted line by line.
      def self.quoted(text)
        shown = text.to_s.length > SHOWN ? "#{text.to_s[0, SHOWN]}\n#{CUT}" : text.to_s
        "> #{Slack::Mrkdwn.escape(shown).gsub("\n", "\n> ")}"
      end

      def self.now(proposal)
        said = proposal.current_wording.present? ? "*The handbook says now*\n#{quoted(proposal.current_wording)}" : "_The handbook says nothing about this yet._"
        { type: "section", text: { type: "mrkdwn", text: said } }
      end

      def self.decided(proposal)
        { type: "context", elements: [ { type: "mrkdwn", text: Slack::Mrkdwn.escape(proposal.decided) } ] }
      end

      def self.actions(proposal)
        editable = proposal.text.to_s.length <= Slack::Modals::EditHandbookProposal::SLACK_INPUT_LIMIT
        { type: "actions", elements: [
          { type: "button", style: "primary", action_id: Identifiers::HANDBOOK_PROPOSAL_ACCEPT, text: { type: "plain_text", text: "Accept" }, value: proposal.id },
          ({ type: "button", action_id: Identifiers::HANDBOOK_PROPOSAL_EDIT, text: { type: "plain_text", text: "Edit" }, value: proposal.id } if editable),
          { type: "button", action_id: Identifiers::HANDBOOK_PROPOSAL_DISMISS, text: { type: "plain_text", text: "Dismiss" }, value: proposal.id }
        ].compact }
      end
    end
  end
end
