# Every few minutes, a read of each pull request Halon follows whose interval has passed, for code hosts that send
# nothing and as the safety net for the ones that do. State is in the database, so a restart loses nothing.
class PullRequestSweepJob < ApplicationJob
  queue_as :background

  def perform
    PullRequestFollowing.sweep!
  end
end
