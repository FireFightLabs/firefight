# Acts on what a code host said about a pull request (PullRequestReviewSignals), off the webhook's request.
class PullRequestReviewSignalJob < ApplicationJob
  queue_as :events

  discard_on ActiveRecord::RecordNotFound

  def perform(environment_row_id, signal, attempt = 0)
    row = IntegrationEnvironment.reachable.find(environment_row_id)
    PullRequestReviewSignals.new(row).receive!(Integrations::PullRequestReviews::Signal.new(**signal.symbolize_keys), attempt: attempt)
  end
end
