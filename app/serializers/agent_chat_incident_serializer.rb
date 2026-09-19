class AgentChatIncidentSerializer < BaseSerializer
  object_as :incident

  attributes(id: { type: :string }, identifier: { type: :string }, name: { type: :string })
end
