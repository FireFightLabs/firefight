# A review a person asked for on a pull request that could not start, and the comment Halon posted there to say why
# (PullRequestReviewRefusalPosting). One per request, named by the delivery's reference, so a delivery sent again never
# says it twice, and one per pull request and reason until a review of it starts again.
class PullRequestReview::Refusal < ApplicationRecord
  RESUME_KIND = "pull_request_review_refusal".freeze

  # Why the review could not start (the reason PullRequestReview::Start refused with).
  HALON_UNAVAILABLE = "halon_unavailable".freeze
  MODEL_NOT_SET_UP = "model_not_set_up".freeze
  NO_CONNECTION = "no_connection".freeze
  NO_ACCESS = "no_access".freeze
  REASONS = [ HALON_UNAVAILABLE, MODEL_NOT_SET_UP, NO_CONNECTION, NO_ACCESS ].freeze

  belongs_to :workspace
  belongs_to :integration_environment, optional: true

  validates :repository, :number, :reference, presence: true
  validates :reason, inclusion: { in: REASONS }

  # The refusal of one request, or nil when it is not said. A request is said once, and a pull request hears the same
  # reason once until a review of it starts again, so a host that asks again at each push is not told again each time.
  # A new reason, or the same one after a review ran meanwhile, is said again. Taken under a lock per pull request, so two
  # requests at once say it once.
  def self.claim!(environment_row, signal, reason:)
    workspace_id = environment_row.integration.workspace_id
    transaction do
      key = Zlib.crc32("pull_request_review_refusal:#{workspace_id}:#{signal.repository.downcase}:#{signal.number}")
      with_connection { |connection| connection.select_value(sanitize_sql_array([ "SELECT pg_advisory_xact_lock(?)::text", key ])) }
      next if said_already?(workspace_id, signal, reason)

      inserted = insert_all([ { workspace_id: workspace_id, integration_environment_id: environment_row.id, repository: signal.repository, number: signal.number,
                                reference: signal.reference, reason: reason, created_at: Time.current, updated_at: Time.current } ],
                            unique_by: %i[workspace_id reference], returning: %w[id])
      find_by(id: inserted.rows.first&.first)
    end
  end

  # The pull request's last refusal gave this reason, and no review of it started since.
  def self.said_already?(workspace_id, signal, reason)
    last = of_pull_request(workspace_id, signal.repository, signal.number).order(:created_at).last
    return false unless last&.reason == reason

    !PullRequestReview.seen.where(workspace_id: workspace_id, number: signal.number).where("lower(repository) = ?", signal.repository.downcase)
                      .where("created_at > ?", last.created_at).exists?
  end
  private_class_method :said_already?

  def self.of_pull_request(workspace_id, repository, number)
    where(workspace_id: workspace_id, number: number).where("lower(repository) = ?", repository.to_s.downcase)
  end

  def posted? = posted_at.present?

  # Kept once the comment went up. False when it went up already.
  def posted!(reference)
    self.class.where(id: id, posted_at: nil).update_all(comment_id: reference&.to_s, posted_at: Time.current, updated_at: Time.current).positive?.tap { |won| reload if won }
  end

  def authorize_post!(tool, arguments, approval_id: nil, &)
    AbilityGateway.authorize!(
      principal: SystemAgent.pull_request_review, action_key: tool.action_key, workspace: workspace, scope: {}, params: arguments,
      context: { source: AbilityGateway::SOURCE_PULL_REQUEST_REVIEW, triggered_by_label: "PR ##{number} in #{repository}", approval_id: approval_id }.compact, &
    )
  end
end
