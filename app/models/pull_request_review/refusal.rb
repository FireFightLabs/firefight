# A review a person asked for on a pull request that could not start, and the comment Halon posted there to say why
# (PullRequestReviewRefusalPosting). One per request, named by the delivery's reference, so a delivery sent again never
# says it twice.
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

  # The refusal of one request, or nil when that request was refused already.
  def self.claim!(environment_row, signal, reason:)
    workspace_id = environment_row.integration.workspace_id
    inserted = insert_all([ { workspace_id: workspace_id, integration_environment_id: environment_row.id, repository: signal.repository, number: signal.number,
                              reference: signal.reference, reason: reason } ], unique_by: %i[workspace_id reference], returning: %w[id])
    find_by(id: inserted.rows.first&.first)
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
