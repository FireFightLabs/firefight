# Removes what a repository's prepared copy installed once no box used it for PreparedCopy::KEPT_UNUSED_FOR, from the
# app's storage or from the provider that keeps it.
class PreparedCopySweepJob < ApplicationJob
  queue_as :background

  def perform
    Integrations::CodeReading.sweep_prepared!
  end
end
