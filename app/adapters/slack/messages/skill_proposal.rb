module Slack
  module Messages
    # A skill Halon proposed in a chat's thread: what it would do, the tools it names and why, with Accept and Dismiss
    # while it waits and the Skills page to edit it first, and who decided once someone did. Steps longer than Slack shows
    # are cut, and the Skills page shows them whole.
    module SkillProposal
      TITLE = ":sparkles:  *Halon proposes a skill*".freeze
      CHANGE_TITLE = ":sparkles:  *Halon proposes a change to a skill*".freeze
      FOOTER = "Nothing changes until someone accepts this.".freeze
      # A section's text holds at most 3,000 characters, with room left for the heading.
      SHOWN = 2_500
      CUT = "_Cut short here. The Skills page shows it whole._".freeze

      # proposal is a SkillProposalService::Shown.
      def self.build(proposal)
        [
          { type: "section", text: { type: "mrkdwn", text: proposal.new_skill ? TITLE : CHANGE_TITLE } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: "*#{Mrkdwn.escape(proposal.name)}*  #{Mrkdwn.escape(proposal.used_when)}\n#{quoted(proposal.steps)}" } },
          { type: "section", text: { type: "mrkdwn", text: "*Tools:* #{proposal.tools.map { |tool| "`#{Mrkdwn.escape(tool)}`" }.join(', ').presence || 'None'}" } },
          { type: "context", elements: [ { type: "mrkdwn", text: "Why: #{Mrkdwn.escape(proposal.reason.truncate(SHOWN))}" } ] },
          (proposal.decided ? decided(proposal) : actions(proposal)),
          ({ type: "context", elements: [ { type: "mrkdwn", text: FOOTER } ] } if proposal.decided.nil?)
        ].compact
      end

      def self.fallback(proposal)
        "Halon proposes #{proposal.new_skill ? 'a skill' : 'a change to the skill'} #{proposal.name}: #{proposal.used_when.truncate(SHOWN)}"
      end

      # Model text, so it is escaped and quoted line by line.
      def self.quoted(text)
        shown = text.to_s.length > SHOWN ? "#{text.to_s[0, SHOWN]}\n#{CUT}" : text.to_s
        "> #{Mrkdwn.escape(shown).gsub("\n", "\n> ")}"
      end

      def self.decided(proposal)
        elements = [ { type: "mrkdwn", text: Mrkdwn.escape(proposal.decided) } ]
        { type: "context", elements: elements }
      end

      def self.actions(proposal)
        { type: "actions", elements: [
          { type: "button", style: "primary", action_id: Identifiers::SKILL_PROPOSAL_ACCEPT, text: { type: "plain_text", text: "Accept" }, value: proposal.id },
          { type: "button", action_id: Identifiers::SKILL_PROPOSAL_DISMISS, text: { type: "plain_text", text: "Dismiss" }, value: proposal.id },
          ({ type: "button", text: { type: "plain_text", text: "Edit on the Skills page" }, url: proposal.page_url } if proposal.page_url)
        ].compact }
      end
    end
  end
end
