# Tells whoever confirmed a memory, and whoever approved it as a lesson for pull request reviews, that Halon's nightly
# check, or an incident's completed postmortem, found evidence against it, each once, by direct message
# (MemoryPostService#tell_people_behind!). incident_id names the incident whose postmortem disputed it, when one did.
class MemoryChallengeJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound
  retry_on(*MemoryPostService::PASSING, wait: :polynomially_longer, attempts: 5)

  def perform(memory_id, incident_id = nil)
    memory = Chat::Memory.find(memory_id)
    MemoryPostService.new(memory.workspace).tell_people_behind!(memory, postmortem_of: memory.workspace.incidents.find_by(id: incident_id))
  end
end
