# Asks people to accept or dismiss a skill Halon proposed. It asks with a card in a dashboard chat, with a message in the
# thread a chat speaks in (a channel's or a person's direct messages), and always on the Skills page. Each place is
# redrawn once someone decides, wherever they decided.
class SkillProposalService
  # What a platform message shows, so the adapter never reads a version record. new_skill says it adds a skill.
  Shown = Data.define(:id, :name, :new_skill, :copy_of, :used_when, :tools, :steps, :reason, :decided, :page_url)

  NOT_POSTED = [ AdapterError::IsArchived, AdapterError::NotFound, AdapterError::NotInChannel ].freeze
  # The chats that speak in a platform thread.
  THREADED_KINDS = [ Conversation::KIND_CHANNEL, Conversation::KIND_DIRECT ].freeze
  GONE = "That proposal is gone. Look on the Skills page.".freeze

  def initialize(workspace)
    @workspace = workspace
  end

  # From a chat. Returns the proposal, or raises ActiveRecord::RecordInvalid with why it was refused.
  def propose!(conversation, name:, content:, reason:)
    proposal = Chat::CustomSkill.propose_for!(@workspace, name: name, content: content, reason: reason, conversation: conversation)
    Conversation::LiveDelivery.skill_proposed(conversation) if conversation&.belongs_to_one_person?
    SkillProposalPostJob.perform_later(proposal.id) if place(conversation)
    proposal
  end

  # Posts it in the thread the chat that proposed it speaks in.
  def post!(proposal)
    channel_id, thread_id = place(proposal.conversation)
    return unless channel_id

    posted = adapter.post_skill_proposal(channel_id: channel_id, thread_id: thread_id, proposal: shown(proposal))
    proposal.update_columns(channel_id: posted[:channel_id] || channel_id, thread_id: thread_id, message_id: posted[:message_id], updated_at: Time.current)
  rescue *NOT_POSTED => error
    Rails.logger.info({ event: "skill_proposal.not_posted", proposal_id: proposal.id, error: error.class.name }.to_json)
  end

  # content and name are the person's edit, when they changed it first.
  def accept!(proposal, by:, content: nil, name: nil)
    skill = proposal.custom_skill
    skill.accept!(proposal, by: by, content: content, name: name || skill.name)
    redraw(proposal.reload)
    skill
  end

  def dismiss!(proposal, by:)
    proposal.custom_skill.dismiss!(proposal, by: by)
    redraw(proposal.reload)
  end

  # Someone pressing Accept or Dismiss on a message. Returns why it was refused, or nil once it was decided.
  def decide!(proposal_id:, member:, accept:)
    proposal = Chat::CustomSkill::Version.joins(:custom_skill).find_by(id: proposal_id.to_s, chat_custom_skills: { workspace_id: @workspace.id },
                                                                       author_kind: Chat::CustomSkill::Version::AUTHOR_HALON)
    return GONE unless proposal

    accept ? accept!(proposal, by: member) : dismiss!(proposal, by: member)
    nil
  rescue Chat::CustomSkill::Writing::Refused => error
    error.message
  rescue ActiveRecord::RecordInvalid => error
    error.record.errors.full_messages.to_sentence
  end

  def shown(proposal)
    skill = proposal.custom_skill
    Shown.new(id: proposal.id, name: skill.name, new_skill: proposal.parent_version_id.nil?, copy_of: skill.library_name,
              used_when: proposal.used_when, tools: proposal.tools, steps: proposal.steps, reason: proposal.reason.to_s,
              decided: proposal.decided_sentence, page_url: page_url(proposal))
  end

  private

  def adapter = @adapter ||= @workspace.adapter

  def place(conversation)
    return nil unless conversation.is_a?(Conversation) && THREADED_KINDS.include?(conversation.kind) && conversation.channel_id.present?

    [ conversation.channel_id, conversation.thread_id ]
  end

  def page_url(proposal)
    options = AppUrl.options
    query = proposal.proposed? ? { HalonSkillsController::PROPOSAL_QUERY => proposal.id } : {}
    options && Rails.application.routes.url_helpers.halon_skills_url(**options, **query)
  end

  def redraw(proposal)
    Conversation::LiveDelivery.skill_proposed(proposal.conversation) if proposal.conversation&.belongs_to_one_person?
    return if proposal.message_id.blank?

    adapter.update_skill_proposal(channel_id: proposal.channel_id, message_id: proposal.message_id, proposal: shown(proposal))
  rescue *NOT_POSTED => error
    Rails.logger.info({ event: "skill_proposal.not_redrawn", proposal_id: proposal.id, error: error.class.name }.to_json)
  end
end
