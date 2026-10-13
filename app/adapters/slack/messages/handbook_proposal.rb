module Slack
  module Messages
    # A handbook edit Halon proposed because something it read contradicted the handbook, or a new page it drafted, with
    # Accept, Edit and Dismiss while it waits, and who decided once someone did. A page longer than Slack shows is cut,
    # and one longer than its form takes is edited on the Handbook page.
    module HandbookProposal
      TITLE = ":ledger:  *Halon proposes a handbook edit*".freeze
      NEW_PAGE_TITLE = ":ledger:  *Halon proposes a handbook page*".freeze
      FOOTER = "Nothing in the handbook changes until someone accepts this.".freeze
      # Slack refuses a section or context text longer than this, counted after escaping.
      TEXT_LIMIT = 3_000
      SHOWN = 2_500
      CUT = "_Cut short here. The Handbook page shows it whole._".freeze

      # proposal is a HandbookProposalService::Shown.
      def self.build(proposal)
        [
          { type: "section", text: { type: "mrkdwn", text: proposal.new_page ? NEW_PAGE_TITLE : TITLE } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: headed("*#{Slack::Mrkdwn.escape(proposal.page_title)}*\n", proposal.text) } },
          (now(proposal) if proposal.decided.nil? && !proposal.new_page),
          { type: "context", elements: [ { type: "mrkdwn", text: "Why: #{clipped(Slack::Mrkdwn.escape(proposal.evidence.to_s), SHOWN, omission: '...')}" } ] },
          (proposal.decided ? decided(proposal) : actions(proposal)),
          ({ type: "context", elements: [ { type: "mrkdwn", text: FOOTER } ] } if proposal.decided.nil?)
        ].compact
      end

      def self.fallback(proposal)
        "Halon proposes #{proposal.new_page ? 'a handbook page' : 'a handbook edit to'} #{proposal.page_title}: #{proposal.text.to_s.truncate(SHOWN)}"
      end

      # A heading, then model and person text escaped and quoted line by line. Escaping can make the text several times
      # longer, so it is cut to what is left of Slack's limit after escaping, never before.
      def self.headed(heading, text)
        quoted = "> #{Slack::Mrkdwn.escape(text.to_s).gsub("\n", "\n> ")}"
        room = [ TEXT_LIMIT - heading.length, SHOWN ].min
        return heading + quoted if quoted.length <= room

        "#{heading}#{clipped(quoted, room - CUT.length - 3)}\n> #{CUT}"
      end

      # Escaped text cut to length without leaving half an entity behind.
      def self.clipped(text, length, omission: "")
        return text if text.length <= length

        text[0, length - omission.length].sub(/&[a-z]*\z/, "") + omission
      end

      def self.now(proposal)
        said = proposal.current_wording.present? ? headed("*The handbook says now*\n", proposal.current_wording) : "_The handbook says nothing about this yet._"
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
