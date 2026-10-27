# What happened to a memory, oldest first, for the Memory page to show how it came to stand where it does.
module Chat::Memory::History
  extend ActiveSupport::Concern

  included do
    has_many :events, -> { in_order }, class_name: "Chat::MemoryEvent", foreign_key: :memory_id, inverse_of: :memory, dependent: :delete_all
  end

  # investigation is the run that checked it, when a run did.
  def record!(kind, actor: nil, member: nil, detail: nil, investigation: nil)
    Chat::MemoryEvent.create!(workspace_id: workspace_id, memory: self, kind: kind, actor: actor, member: member, detail: detail.presence, investigation: investigation)
  end
end
