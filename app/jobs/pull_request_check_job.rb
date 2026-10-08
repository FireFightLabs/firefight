# One read of a pull request Halon opened, from the sweep, right after it opened or changed, or at once when its code host
# said something about it. One another worker is reading is left to it (CodeAgentSession#claim_pull_request_check!).
class PullRequestCheckJob < ApplicationJob
  queue_as :background

  def perform(session_id)
    session = CodeAgentSession.find_by(id: session_id)
    PullRequestFollowing.check!(session) if session
  end
end
