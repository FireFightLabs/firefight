# One of Halon's suggestions waiting on the canvas, with what the canvas needs to draw it over the version: a new step
# dashed, a removed one struck, a connection added or taken away, each changed field's old value beside the new one,
# Halon's reason and the chat or run it came from.
class WorkflowSuggestionSerializer < BaseSerializer
  object_as :suggestion

  type :string
  def id
    suggestion.id
  end

  type :string
  def change_set_id
    suggestion.change_set_id.to_s
  end

  type "#{Workflow::Edit::OPERATIONS.map(&:inspect).join(' | ')}"
  def operation
    suggestion.operation
  end

  type :string
  def words
    suggestion.suggestion_words
  end

  type :string, optional: true
  def reason
    suggestion.reason
  end

  # The step it touches, or the one it adds.
  type :string, optional: true
  def step_id
    payload["step_id"].presence || payload.dig("step", "id")
  end

  # The step it adds, drawn dashed where Halon placed it.
  has_one :added_step, serializer: WorkflowStepNodeSerializer, optional: true do
    Workflow::Version::Placed.new(step: payload["step"].to_h, within: payload["within"].presence) if suggestion.operation == Workflow::Edit::OPERATION_ADD_STEP
  end

  type "{ from: string; to: string; route: string | null; within: string | null }", optional: true
  def edge
    return unless [ Workflow::Edit::OPERATION_CONNECT, Workflow::Edit::OPERATION_DISCONNECT ].include?(suggestion.operation)

    { from: payload["from"].to_s, to: payload["to"].to_s, route: payload["route"].presence, within: payload["within"].presence }
  end

  type "{ field: string; before: string | null; after: string | null }[]"
  def changes
    suggestion.changes_against(options[:document]).map { |change| { field: change.field, before: change.before, after: change.after } }
  end

  type :string, optional: true
  def source_label
    return "a chat with Halon" if suggestion.source_chat
    return "a run on #{suggestion.source_run.created_at.utc.strftime('%b %-d')}" if suggestion.source_run

    nil
  end

  type :string, optional: true
  def source_href
    conversation = suggestion.source_chat&.owner
    return Rails.application.routes.url_helpers.agent_chat_path(conversation) if conversation.is_a?(Conversation)

    nil
  end

  type :string, optional: true
  def source_run_id
    suggestion.source_run_id
  end

  type :string
  def created_at
    suggestion.created_at.iso8601
  end

  private

  def payload = suggestion.payload.to_h
end
