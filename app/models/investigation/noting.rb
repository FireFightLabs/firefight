# What responders add while a run works. A note waits on the run's chat and joins it at the agent's next step, so a
# person can steer a run without stopping it.
module Investigation::Noting
  extend ActiveSupport::Concern

  NOTE_AFTER_THE_END = "This investigation has finished, so it cannot take anything more.".freeze
  NOTE_EMPTY = "Write what Halon should know first.".freeze
  NOTE_ADDED = "Added. Halon reads it at its next step.".freeze
  UNNAMED_RESPONDER = "A responder".freeze

  def note_blocked_reason(text = nil)
    return NOTE_AFTER_THE_END unless live?

    NOTE_EMPTY if text && text.strip.empty?
  end

  def add_note!(text, by:)
    chat_record.queue_message!(text, sender: by)
  end

  # From a platform thread, where no controller has checked the permission. Whoever may start a run may add to one.
  # Returns why the note was not added, or nil once it waits for the run.
  def add_note_from(text, member:, source:)
    blocked = note_blocked_reason(text)
    return blocked if blocked
    return not_allowed(member) unless member

    AbilityGateway.authorize!(
      principal: member, workspace: workspace,
      action_key: Ability::Action.system_key(Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE),
      context: { source: source, incident_id: incident_id }
    )
    add_note!(text.strip, by: member)
    nil
  rescue AbilityGateway::Denied, AbilityGateway::PendingApproval
    not_allowed(member)
  end

  # A run acts as the agent, and a note can come from any responder, so each says who added it.
  def take_notes!
    return [] unless chat

    chat.take_queued! { |note| "#{note.sender&.display_name || UNNAMED_RESPONDER} added: #{note.content}" }
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
