module Operator
  # A Halon chat for the chats list and the trace header.
  class HalonChatSerializer < BaseSerializer
    object_as :conversation

    KIND_UNION = Conversation::KINDS.map(&:inspect).join(" | ")

    type :string
    def id = conversation.id

    # The chat's saved title, or the default title when it has none.
    type :string
    def title = conversation.title.presence || Conversation::UNTITLED

    type KIND_UNION
    def kind = conversation.kind

    type :string
    def workspace_name = conversation.workspace.name

    type :string, optional: true
    def incident_label
      subject = conversation.subject
      subject.is_a?(Incident) ? subject.identifier : nil
    end

    type :number
    def turns = conversation.turns_used

    type :number
    def spent_micros = conversation.spent_micros

    type :string
    def updated_at = conversation.updated_at.utc.iso8601
  end
end
