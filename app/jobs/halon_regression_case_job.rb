# Replays one rated answer for a regression run. Two at a time across every run, since each replay is a whole
# investigation on the model.
class HalonRegressionCaseJob < ApplicationJob
  queue_as :background
  limits_concurrency key: "halon_regression", to: 2, duration: Investigation::RegressionResult::STALE_AFTER

  discard_on ActiveRecord::RecordNotFound
  notices_interruptions

  def perform(result_id)
    result = Investigation::RegressionResult.find(result_id)
    return Investigation::Regression.settle_lost!(result) if interrupted_at

    Investigation::Regression.run_case!(result)
  end
end
