# What responders add while a run works. A note waits on the run's chat and joins it at the agent's next step, so a
# person can steer a run without stopping it.
module Investigation::Noting
  extend ActiveSupport::Concern

  NOTE_AFTER_THE_END = "This investigation has finished, so it cannot take anything more.".freeze
  NOTE_EMPTY = "Write what Halon should know first.".freeze
  NOTE_ADDED = "Added. Halon reads it at its next step.".freeze
  UNNAMED_RESPONDER = "A responder".freeze
  FILES_WITH_THE_ASK = "Shared when asking for this run.".freeze

  def note_blocked_reason(text = nil)
    return NOTE_AFTER_THE_END unless live?

    NOTE_EMPTY if text && text.strip.empty?
  end

  def add_note!(text, by:, files: [])
    chat_record.queue_message!(text, sender: by, files: files)
  end

  # Files handed over as a run starts wait for it like notes, as many to a note as a person may send with one message.
  def hand_over_files!(files, by:)
    files.each_slice(Chat::Attachment::MAX_PER_MESSAGE) { |group| add_note!(FILES_WITH_THE_ASK, by: by, files: group) }
  end

  # From a platform thread, where no controller has checked the permission. Whoever may start a run may add to one.
  # Files alone are a note. Returns why the note was not added, or nil once it waits for the run.
  def add_note_from(text, member:, source:, files: [])
    blocked = note_blocked_reason(files.empty? ? text : nil)
    return blocked if blocked
    return not_allowed(member) unless member

    AbilityGateway.authorize!(
      principal: member, workspace: workspace,
      action_key: Ability::Action.system_key(Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE),
      context: { source: source, incident_id: incident_id }
    )
    add_note!(text.to_s.strip, by: member, files: files)
    nil
  rescue AbilityGateway::Denied, AbilityGateway::PendingApproval
    not_allowed(member)
  end

  # A run acts as the agent, and a note can come from any responder, so each says who added it.
  def take_notes!
    return [] unless chat

    chat.take_queued! do |note|
      name = note.sender&.display_name || UNNAMED_RESPONDER
      note.content.present? ? "#{name} added: #{note.content}" : "#{name} added #{note.attached_files.size == 1 ? 'a file' : 'files'}."
    end
  end

  def notes = chat ? chat.queued_messages.includes(:sender).order(:created_at, :id) : Chat::QueuedMessage.none

  # A note can arrive before the worker opens the chat, so either may open it. The worker names the model it runs on.
  def chat_record(model = ai_model)
    chat || Chat.open!(owner: self, workspace: workspace, model_choice: model).tap { |opened| self.chat = opened }
  rescue ActiveRecord::RecordNotUnique
    reload_chat
  end

  def ai_model = model_choice || FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: workspace)

  private

  def not_allowed(member) = "#{member&.display_name || "You"} may not add to an investigation."
end
