# Replays one chat bench scenario. Four at a time across every run, since each replay is a whole chat on the model.
class HalonBenchCaseJob < ApplicationJob
  queue_as :background
  limits_concurrency key: "halon_bench", to: Conversation::Bench::AT_ONCE, duration: Conversation::BenchResult::STALE_AFTER

  discard_on ActiveRecord::RecordNotFound
  notices_interruptions

  def perform(result_id)
    result = Conversation::BenchResult.find(result_id)
    return Conversation::Bench.settle_lost!(result) if interrupted_at

    Conversation::Bench.run_case!(result)
  end
end
