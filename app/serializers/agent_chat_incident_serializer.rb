# An incident the person can point the agent at with @.
class AgentChatIncidentSerializer < BaseSerializer
  object_as :incident

  attributes(id: { type: :string }, identifier: { type: :string }, name: { type: :string })
end
