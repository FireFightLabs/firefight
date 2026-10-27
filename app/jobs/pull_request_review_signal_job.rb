# Acts on what a code host said about a pull request (PullRequestReviewSignals), off the webhook's request.
class PullRequestReviewSignalJob < ApplicationJob
  queue_as :events

  # A signal waits for line comments to be read back first, so their threads get its push or its reply.
  retry_on PullRequestReviewPosting::NotPosted, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(environment_row_id, signal, attempt = 0)
    row = IntegrationEnvironment.reachable.find(environment_row_id)
    PullRequestReviewSignals.new(row).receive!(Integrations::PullRequestReviews::Signal.new(**signal.symbolize_keys), attempt: attempt)
  end
end
