# Posts a skill Halon proposed in the thread its chat speaks in. A platform hiccup only loses the message, never the
# proposal, which waits on the Skills page either way.
class SkillProposalPostJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(proposal_id)
    proposal = Chat::CustomSkill::Version.find(proposal_id)
    return unless proposal.proposed? && proposal.message_id.blank?

    SkillProposalService.new(proposal.custom_skill.workspace).post!(proposal)
  end
end
