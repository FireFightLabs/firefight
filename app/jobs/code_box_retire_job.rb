# Stops a box a run moved away from, to a copy of a prepared repository, once calls still reading in it are done.
class CodeBoxRetireJob < ApplicationJob
  queue_as :background

  def perform(provider_key, ref)
    Integrations::CodeReading.retire(provider_key, ref)
  end
end
