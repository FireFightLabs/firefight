# Picks up what a stopped worker left part way, by a deploy or a crash, so nothing waits on a worker that is gone. Each
# kind either runs again or ends saying so where its person looks, once (docs/architecture.md, Deploys).
class RecoverySweepJob < ApplicationJob
  # The events worker only takes short jobs, so the sweep never waits behind a long run.
  queue_as :events
  # One at a time, and a sweep due while one runs is dropped, since the next minute's covers it.
  limits_concurrency key: name, duration: 10.minutes, on_conflict: :discard

  def perform
    InterruptedWork.recover!
  end
end
