# Tells the person who confirmed a memory that Halon's nightly check found evidence against it, once, by direct message
# (MemoryPostService#tell_confirmer!).
class MemoryChallengeJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound
  retry_on(*MemoryPostService::PASSING, wait: :polynomially_longer, attempts: 5)

  def perform(memory_id)
    memory = Chat::Memory.find(memory_id)
    MemoryPostService.new(memory.workspace).tell_confirmer!(memory)
  end
end
