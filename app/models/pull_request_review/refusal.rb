# A review a person asked for on a pull request that could not start, and the comment Halon posts there to say why
# (PullRequestReviewRefusalPosting). One per request, named by the delivery's reference, so a delivery sent again never
# says it twice. Only a refusal that went up or may still go up (pending, held or posted) counts as said, so one that was
# denied, declined, refused by the host or gave up never silences the next request.
class PullRequestReview::Refusal < ApplicationRecord
  RESUME_KIND = "pull_request_review_refusal".freeze

  # Why the review could not start (the reason PullRequestReview::Start refused with).
  HALON_UNAVAILABLE = "halon_unavailable".freeze
  MODEL_NOT_SET_UP = "model_not_set_up".freeze
  NO_CONNECTION = "no_connection".freeze
  NO_ACCESS = "no_access".freeze
  REASONS = [ HALON_UNAVAILABLE, MODEL_NOT_SET_UP, NO_CONNECTION, NO_ACCESS ].freeze

  # Where the comment stands. Waiting for its job, held for an approval, posted, or dropped with why.
  STATUS_PENDING = "pending".freeze
  STATUS_HELD = "held".freeze
  STATUS_POSTED = "posted".freeze
  STATUS_DROPPED = "dropped".freeze
  STATUSES = [ STATUS_PENDING, STATUS_HELD, STATUS_POSTED, STATUS_DROPPED ].freeze
  SAID = [ STATUS_PENDING, STATUS_HELD, STATUS_POSTED ].freeze
  LIVE = [ STATUS_PENDING, STATUS_HELD ].freeze

  # A person asking again in a comment with the same reason is answered at most this often on one pull request, so
  # comments on a public repository cannot make Halon post without end.
  COMMENT_ANSWER_EVERY = 10.minutes

  belongs_to :workspace
  belongs_to :integration_environment, optional: true

  validates :repository, :number, :reference, presence: true
  validates :reason, inclusion: { in: REASONS }
  validates :status, inclusion: { in: STATUSES }

  scope :said, -> { where(status: SAID) }

  # The refusal of one request, or nil when it is not said. A request is said once. A refusal held for an approval with
  # the same reason is waited on rather than asked for again. A comment that asks is a person asking now and hears it,
  # at most once every COMMENT_ANSWER_EVERY for the same reason. Any other request, as Firefight picked as a reviewer,
  # which a host may count again at each push, hears the same reason once per pull request until a review of it starts
  # again. Taken under a lock per pull request, so two requests at once say it once.
  def self.claim!(environment_row, signal, reason:)
    workspace_id = environment_row.integration.workspace_id
    transaction do
      key = Zlib.crc32("pull_request_review_refusal:#{workspace_id}:#{signal.repository.downcase}:#{signal.number}")
      with_connection { |connection| connection.select_value(sanitize_sql_array([ "SELECT pg_advisory_xact_lock(?)::text", key ])) }
      same = of_pull_request(workspace_id, signal.repository, signal.number)
      next if same.where(reason: reason, status: STATUS_HELD).any?(&:still_said?)
      next if signal.comment.present? ? same.said.where(reason: reason).where(created_at: COMMENT_ANSWER_EVERY.ago..).any?(&:still_said?) : said_already?(same, reason)

      now = Time.current
      inserted = insert_all([ { workspace_id: workspace_id, integration_environment_id: environment_row.id, repository: signal.repository, number: signal.number,
                                reference: signal.reference, reason: reason, status: STATUS_PENDING, created_at: now, updated_at: now } ],
                            unique_by: %i[workspace_id reference], returning: %w[id])
      find_by(id: inserted.rows.first&.first)
    end
  end

  def self.of_pull_request(workspace_id, repository, number)
    where(workspace_id: workspace_id, number: number).where("lower(repository) = ?", repository.to_s.downcase)
  end

  # The pull request's last refusal that was said gave this reason, and no review of it started since.
  def self.said_already?(same, reason)
    last = same.said.order(:created_at).select(&:still_said?).last
    last&.reason == reason && !last.superseded?
  end
  private_class_method :said_already?

  def posted? = status == STATUS_POSTED

  def live? = LIVE.include?(status)

  # Posted, waiting for its job, or held on an approval that may still let it go up. One whose approval lapsed or was
  # decided against is not said, whatever its status still reads.
  def still_said?
    return false unless SAID.include?(status)
    return true unless status == STATUS_HELD

    approval = Ability::Approval.find_by(id: held_approval_id)
    approval.present? && (approval.pending? || approval.usable?)
  end

  # A review of the pull request started after this refusal, so it says nothing true any more.
  def superseded?
    PullRequestReview.seen.where(workspace_id: workspace_id, number: number).where("lower(repository) = ?", repository.downcase)
                     .where("created_at > ?", created_at).exists?
  end

  # Kept once the comment went up. False when it went up or was dropped already.
  def posted!(reference) = move!(LIVE, status: STATUS_POSTED, comment_id: reference&.to_s, posted_at: Time.current)

  # Held on an approval, which a later request of the same reason waits on.
  def held!(approval) = move!(LIVE, status: STATUS_HELD, held_approval_id: approval.id)

  # Not said, and why, so it no longer counts as said.
  def dropped!(why) = move!(LIVE, status: STATUS_DROPPED, dropped_reason: why.to_s.truncate(500))

  # The first time the comment was tried, kept so a later try reads the conversation first.
  def attempted! = self.class.where(id: id, attempted_at: nil).update_all(attempted_at: Time.current, updated_at: Time.current).tap { reload }

  def authorize_post!(tool, arguments, approval_id: nil, &)
    AbilityGateway.authorize!(
      principal: SystemAgent.pull_request_review, action_key: tool.action_key, workspace: workspace, scope: {}, params: arguments,
      context: { source: AbilityGateway::SOURCE_PULL_REQUEST_REVIEW, triggered_by_label: "PR ##{number} in #{repository}", approval_id: approval_id }.compact, &
    )
  end

  private

  def move!(from, **changes)
    self.class.where(id: id, status: from).update_all(changes.merge(updated_at: Time.current)).positive?.tap { |won| reload if won }
  end
end
