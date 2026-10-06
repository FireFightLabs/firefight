# A chat or a run that was handed a memory at its start, so the memory counts as used once for it.
class Chat::MemoryUse < ApplicationRecord
  self.table_name = "chat_memory_uses"

  belongs_to :memory, class_name: "Chat::Memory"
  belongs_to :owner, polymorphic: true
end
