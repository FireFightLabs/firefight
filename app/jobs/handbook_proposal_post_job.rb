# Posts a handbook edit Halon proposed in the incident thread its chat or run speaks in. A platform hiccup only loses the
# message, never the proposal, which waits on the Handbook page either way.
class HandbookProposalPostJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(proposal_id)
    proposal = Chat::HandbookProposal.find(proposal_id)
    return unless proposal.pending? && proposal.message_id.blank?

    HandbookProposalService.new(proposal.workspace).post!(proposal)
  end
end
