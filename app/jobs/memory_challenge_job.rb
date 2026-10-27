# Tells whoever confirmed a memory, and whoever approved it as a lesson for pull request reviews, that Halon's nightly
# check found evidence against it, each once, by direct message (MemoryPostService#tell_people_behind!).
class MemoryChallengeJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound
  retry_on(*MemoryPostService::PASSING, wait: :polynomially_longer, attempts: 5)

  def perform(memory_id)
    memory = Chat::Memory.find(memory_id)
    MemoryPostService.new(memory.workspace).tell_people_behind!(memory)
  end
end
