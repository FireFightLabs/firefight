# Asks people to accept, edit or dismiss a handbook edit or new page Halon proposed. It asks with a card in a dashboard
# chat, with a message in the incident thread a chat or run speaks in, and always on the Handbook page. Each place is redrawn once
# someone decides.
class HandbookProposalService
  # What a platform message shows, so the adapter never reads a proposal record. new_page says it adds a page.
  Shown = Data.define(:id, :page_title, :new_page, :current_wording, :text, :evidence, :decided)

  NOT_POSTED = [ AdapterError::IsArchived, AdapterError::NotFound, AdapterError::NotInChannel ].freeze

  def initialize(workspace)
    @workspace = workspace
  end

  # From a chat or run. Returns the proposal, or raises ActiveRecord::RecordInvalid with why it was refused.
  def propose!(owner, text:, evidence:, page: nil, title: nil)
    proposal = Chat::HandbookProposal.propose!(owner, page: page, title: title, text: text, evidence: evidence)
    conversation = proposal.conversation
    if conversation&.personal?
      Conversation::LiveDelivery.handbook_proposed(conversation)
    elsif place(owner)
      HandbookProposalPostJob.perform_later(proposal.id)
    end
    proposal
  end

  # Posts it where the chat or run that proposed it speaks in its incident's channel.
  def post!(proposal)
    channel_id, thread_id = place(proposal.conversation || proposal.investigation)
    return unless channel_id

    posted = adapter.post_handbook_proposal(channel_id: channel_id, thread_id: thread_id, proposal: shown(proposal))
    proposal.update!(channel_id: posted[:channel_id] || channel_id, thread_id: thread_id, message_id: posted[:message_id])
  rescue *NOT_POSTED => error
    Rails.logger.info({ event: "handbook_proposal.not_posted", proposal_id: proposal.id, error: error.class.name }.to_json)
  end

  # Returns the wording written, or nil with the proposal's refusal left to read. text is the person's edit, when any.
  def accept!(proposal, by:, text: nil)
    written = proposal.accept!(by: by, text: text)
    return nil unless written

    HandbookService.new(@workspace).indexed!(written.handbook_page)
    redraw(proposal)
    written
  end

  def dismiss!(proposal, by:)
    dismissed = proposal.dismiss!(by: by)
    redraw(proposal) if dismissed
    dismissed
  end

  GONE = "That proposal is gone. Look on the Handbook page.".freeze
  EMPTY = "Write what the handbook should say.".freeze

  # Someone pressing Accept or Dismiss on a message. Returns why it was refused, or nil once it was decided.
  def decide!(proposal_id:, member:, accept:)
    proposal = find(proposal_id)
    return GONE unless proposal
    return proposal.accept_blocked_reason || (accept!(proposal, by: member) ? nil : proposal.accept_blocked_reason || GONE) if accept

    proposal.dismiss_blocked_reason || (dismiss!(proposal, by: member) ? nil : proposal.dismiss_blocked_reason || GONE)
  rescue ActiveRecord::RecordInvalid => error
    error.record.errors.full_messages.to_sentence
  end

  # What the edit form shows, or why it cannot be edited, such as someone having decided it first.
  def editable(proposal_id)
    proposal = find(proposal_id)
    return GONE unless proposal

    proposal.accept_blocked_reason || shown(proposal)
  end

  # The edit form's submission. Returns why it was refused, or nil once the edited wording was written.
  def edit!(proposal_id:, member:, text:)
    proposal = find(proposal_id)
    return GONE unless proposal
    return EMPTY if text.blank?

    proposal.accept_blocked_reason || (accept!(proposal, by: member, text: text) ? nil : proposal.accept_blocked_reason || GONE)
  rescue ActiveRecord::RecordInvalid => error
    error.record.errors.full_messages.to_sentence
  end

  def shown(proposal)
    Shown.new(id: proposal.id, page_title: proposal.page_title, new_page: proposal.title.present?, current_wording: proposal.current_wording,
              text: proposal.result&.text || proposal.text, evidence: proposal.evidence, decided: proposal.decided_sentence)
  end

  private

  def adapter = @adapter ||= @workspace.adapter

  def find(id) = Chat::HandbookProposal.find_by(workspace: @workspace, id: id.to_s)

  # A chat in an incident's channel answers in its thread, and a run speaks in its incident's channel. A dashboard or
  # MCP chat has no channel, so its proposal waits on the Handbook page.
  def place(owner)
    return nil unless owner
    return [ owner.channel_id, owner.thread_id ] if owner.is_a?(Conversation) && owner.kind == Conversation::KIND_CHANNEL && owner.channel_id.present?

    channel_id = owner.incident&.channel_id if owner.is_a?(Investigation)
    return nil if channel_id.blank?

    [ channel_id, (owner.thread_id if owner.channel_id == channel_id) ]
  end

  def redraw(proposal)
    Conversation::LiveDelivery.handbook_proposed(proposal.conversation) if proposal.conversation&.personal?
    return if proposal.message_id.blank?

    adapter.update_handbook_proposal(channel_id: proposal.channel_id, message_id: proposal.message_id, proposal: shown(proposal))
  rescue *NOT_POSTED => error
    Rails.logger.info({ event: "handbook_proposal.not_redrawn", proposal_id: proposal.id, error: error.class.name }.to_json)
  end
end
