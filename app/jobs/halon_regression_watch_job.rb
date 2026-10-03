# Starts a regression run the first time a new version of Halon's prompt is deployed, and settles cases whose worker
# was lost.
class HalonRegressionWatchJob < ApplicationJob
  queue_as :background

  def perform
    Investigation::Regression.settle_stale!
    run = Investigation::Regression.start_for_prompt_change!
    Rails.logger.info({ event: "halon_regression.started", run_id: run.id, cases: run.results.size }.to_json) if run
  end
end
