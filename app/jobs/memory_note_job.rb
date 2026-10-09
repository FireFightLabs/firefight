# Tells an incident's channel that a chat or run working on it learned a memory or disputed one. A platform hiccup only
# loses the note, never the memory, which waits on the Memory page either way.
class MemoryNoteJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(memory_id, kind, owner)
    memory = Chat::Memory.find(memory_id)
    MemoryPostService.new(memory.workspace).note!(memory, kind: kind, owner: owner)
  end
end
