# A code change that opened a pull request owns it for its whole life: Halon follows it until it is merged or closed,
# and tells whoever asked when it conflicts with its base, a check fails or a reviewer asks for changes. Each move is
# one guarded update, so two workers or a live update arriving with the sweep never say anything twice.
module CodeAgentSession::PullRequest
  extend ActiveSupport::Concern

  # Read this often while it is new and changing, less once it has sat a day, and at once on a code host's live update.
  FOLLOW_EVERY = 10.minutes
  FOLLOW_EVERY_LATER = 1.hour
  SETTLED_AFTER = 1.day
  # A check that has not let go of its claim in this long belonged to a worker that died.
  CLAIM_LAPSES = 5.minutes
  # A push or a merge to its base moves what the host says only once it has worked it out, so a live update waits this long.
  NUDGE_WAIT = 30.seconds

  included do
    belongs_to :integration_environment, optional: true
    has_many :notices, -> { order(:created_at, :id) }, class_name: "CodeAgentSession::Notice", foreign_key: :session_id,
                                                         dependent: :delete_all, inverse_of: :session

    scope :following, -> { where(pull_request_state: Integrations::PullRequests::OPEN) }
  end

  class_methods do
    def opened_pull_request(workspace, repository, number)
      return if number.blank?

      where(workspace_id: workspace.id, repository: repository, pull_request_number: number.to_i).order(:created_at).first
    end

    def opened_pull_request?(workspace, repository, number) = opened_pull_request(workspace, repository, number).present?

    # Followed and not read within its interval, or held by a worker that died.
    def follow_due(now = Time.current)
      following.where("pull_request_checked_at IS NULL OR (pull_request_checked_at <= ? AND created_at > ?) OR pull_request_checked_at <= ?",
                      now - FOLLOW_EVERY, now - SETTLED_AFTER, now - FOLLOW_EVERY_LATER)
    end
  end

  def following? = pull_request_state == Integrations::PullRequests::OPEN

  def pull_request_label = "PR ##{pull_request_number} in #{repository}"

  # Kept once the pull request opened, with where Halon follows it from. Only a change asked for where someone can be
  # told is followed, so a change nobody asked for in person opens its pull request and is left to people.
  def owns_pull_request!(environment_row:, number:, url:, base:, branch:)
    update!(integration_environment: environment_row, pull_request_number: number, pull_request_url: url, pull_request_base: base,
            pull_request_branch: branch, pull_request_state: (Integrations::PullRequests::OPEN if someone_to_tell?))
    check_soon! if following?
  end

  # A chat a person reads, or a fix whose run has a thread. An outside agent's chat over MCP has nobody to press Fix it.
  def someone_to_tell?
    case place
    when Conversation then !place.mcp?
    when Investigation::RemediationStep then true
    else false
    end
  end

  def check_soon!(wait: NUDGE_WAIT)
    PullRequestCheckJob.set(wait: wait).perform_later(id) if following?
  end

  # Takes it for one read. False when another worker holds it or it is no longer followed.
  def claim_pull_request_check!(now = Time.current)
    self.class.where(id: id, pull_request_state: Integrations::PullRequests::OPEN)
        .where("pull_request_check_claimed_at IS NULL OR pull_request_check_claimed_at < ?", now - CLAIM_LAPSES)
        .update_all(pull_request_check_claimed_at: now) == 1
  end

  def release_pull_request_check!(now = Time.current)
    self.class.where(id: id).update_all(pull_request_check_claimed_at: nil, pull_request_checked_at: now)
  end

  # Merged or closed ends it, once. False when it had ended.
  def stop_following!(state)
    moved = self.class.where(id: id, pull_request_state: Integrations::PullRequests::OPEN)
                      .update_all(pull_request_state: state, pull_request_ended_at: Time.current, updated_at: Time.current)
    reload
    moved == 1
  end
end
