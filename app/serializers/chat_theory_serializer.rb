# One candidate cause on Halon's theory board in a chat, drawn under the step that last updated the board.
class ChatTheorySerializer < BaseSerializer
  object_as :theory

  attributes(id: { type: :string }, title: { type: :string }, status: { type: :string }, leading: { type: :boolean })

  type "string | null"
  def evidence = theory.evidence

  # The update_theories call that wrote the board as it is now, which the page draws it under.
  type :string
  def tool_call_id = theory.tool_call_id.to_s
end
