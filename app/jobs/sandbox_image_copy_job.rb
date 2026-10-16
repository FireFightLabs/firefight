# Makes a provider's copy of the sandbox image this deployment runs, so the first run after a deploy starts from it
# rather than waiting for the pull. Enqueued by each sweep. Only one call claims the copy, so a repeat does nothing.
class SandboxImageCopyJob < ApplicationJob
  queue_as :background

  def perform(provider_key)
    Integrations::CodeReading.prepare_image!(provider_key)
  end
end
