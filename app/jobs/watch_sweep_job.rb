# Every minute, a check for each active watch not checked within the last minute. State is in the database, so a
# restart loses nothing and the next sweep carries on.
class WatchSweepJob < ApplicationJob
  queue_as :background

  def perform
    Chat::Watch.due.pluck(:id).each { |id| WatchCheckJob.perform_later(id) }
  end
end
