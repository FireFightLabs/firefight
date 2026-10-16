# Makes a provider's copy of the sandbox image this deployment runs for one workspace, so its first run after a deploy
# starts from it rather than waiting for the pull. Enqueued by each sweep for the workspaces that ran boxes lately. Only
# one call claims the copy, so a repeat does nothing. A job queued before copies were kept per workspace names none.
class SandboxImageCopyJob < ApplicationJob
  queue_as :background

  def perform(provider_key, workspace_id = nil)
    return if workspace_id.blank?

    Integrations::CodeReading.prepare_image!(provider_key, workspace_id)
  end
end
