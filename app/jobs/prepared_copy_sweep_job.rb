# Removes what a repository's prepared copy installed once no box used it for PreparedCopy::KEPT_UNUSED_FOR.
class PreparedCopySweepJob < ApplicationJob
  queue_as :background

  def perform
    PreparedCopy.sweep!
  end
end
