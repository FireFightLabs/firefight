# A postmortem's decisions on memories were credited to whoever generated its draft. They now belong to whoever marked it
# completed, or to no person when that was a key or an agent, and each remembers the postmortem that made it.
class CreditPostmortemMemoryDecisions < ActiveRecord::Migration[8.1]
  AGREES = "The postmortem agrees".freeze
  SAYS_OTHERWISE = "The postmortem says otherwise".freeze

  def up
    Chat::Memory.reset_column_information
    Chat::Memory.where(state_reason: [ AGREES, SAYS_OTHERWISE ], source_type: Incident.name).includes(source: :postmortem).find_each do |memory|
      postmortem = memory.source&.postmortem
      next unless postmortem

      completer = postmortem.completed_by
      person = completer.id if completer.is_a?(WorkspaceMembership)
      if memory.state_reason == AGREES
        memory.update_columns(confirmed_by_id: person, decided_by_postmortem_id: postmortem.id)
      else
        memory.update_columns(rejected_by_id: person, decided_by_postmortem_id: postmortem.id)
        memory.replaced_by&.update_columns(confirmed_by_id: person, added_by_id: person, decided_by_postmortem_id: postmortem.id)
      end
    end
  end

  # The draft's author is not kept on the memory, so the old credit cannot be put back.
  def down; end
end
