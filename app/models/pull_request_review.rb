# Halon's review of one pull request: what it read, how risky it judged the change and the findings it verified, written
# one at a time as each was checked. It reads through the code host connection that sees the repository, and outlives
# that connection, so what it caught stays countable. A rehearsal is a review run to measure Halon, such as the bench,
# which nobody in the workspace sees and nothing posts.
class PullRequestReview < ApplicationRecord
  include PullRequestReview::Announcing
  include PullRequestReview::Posting
  include PullRequestReview::Holding
  include PullRequestReview::Requesting
  include PullRequestReview::Lessons
  include PullRequestReview::StrictCheck

  STATUS_QUEUED = "queued"
  STATUS_RUNNING = "running"
  STATUS_DONE = "done"
  STATUS_FAILED = "failed"
  STATUSES = [ STATUS_QUEUED, STATUS_RUNNING, STATUS_DONE, STATUS_FAILED ].freeze
  LIVE_STATUSES = [ STATUS_QUEUED, STATUS_RUNNING ].freeze

  # Someone asked for it on the pull request, or the workspace reviews every pull request when it opens.
  TRIGGER_REQUESTED = "requested"
  TRIGGER_AUTOMATIC = "automatic"
  TRIGGERS = [ TRIGGER_REQUESTED, TRIGGER_AUTOMATIC ].freeze

  RISK_LOW = "low"
  RISK_MEDIUM = "medium"
  RISK_HIGH = "high"
  RISKS = [ RISK_LOW, RISK_MEDIUM, RISK_HIGH ].freeze

  # A worker renews this as it goes, so a dead one holds the review for at most this long.
  LEASE = 10.minutes
  # A review taken this many times keeps losing its worker, and may be what is killing it.
  MAX_ATTEMPTS = 3

  # The plain sentences a review stops with. Anything else in error_summary is a technical cause for whoever debugs it.
  COULD_NOT_READ = "Could not read the pull request from the code host".freeze
  NO_CONNECTION = "The code host connection it read through is gone".freeze
  GAVE_UP = "Something went wrong on Halon's side".freeze
  OUT_OF_CREDIT = "No AI account could pay for the review".freeze
  TOO_MANY_ATTEMPTS = "Its worker kept stopping before it finished".freeze

  belongs_to :workspace
  belongs_to :integration_environment, optional: true
  # Checks first, since each may name a finding.
  has_many :checks, class_name: "PullRequestReview::Check", dependent: :destroy, inverse_of: :review
  has_many :findings, -> { order(:position) }, class_name: "PullRequestReview::Finding", dependent: :destroy, inverse_of: :review
  # The review's own chat with the model, kept for whoever debugs a finding. Each part of a large pull request is a run
  # over it, so what one part read is never lost to the next.
  has_one :chat, as: :owner, dependent: :destroy

  validates :repository, :head_sha, presence: true
  validates :number, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :trigger, inclusion: { in: TRIGGERS }
  validates :risk, inclusion: { in: RISKS }, allow_nil: true
  validates :max_spend_cents, numericality: { only_integer: true, greater_than: 0 }

  scope :live, -> { where(status: LIVE_STATUSES) }
  # The reviews people see. A rehearsal is never one, wherever reviews are listed or counted.
  scope :seen, -> { where(rehearsal: false) }
  scope :of_pull_request, ->(repository, number) { where(repository: repository, number: number) }

  def integration = integration_environment&.integration

  def live? = LIVE_STATUSES.include?(status)

  def done? = status == STATUS_DONE

  def failed? = status == STATUS_FAILED

  def worn_out? = attempts > MAX_ATTEMPTS

  # One box for the whole review, every part and every verification reading the same checkout.
  def code_box_key = "#{CODE_BOX_PREFIX}#{id}"
  CODE_BOX_PREFIX = "pr-review-".freeze

  def spent_cents = (spent_micros / FirefightAi::AgentLoop::MICROS_PER_CENT.to_f).round(2)

  # Takes the review for one worker. A queued review, or a running one whose worker stopped renewing its lease, or one
  # the same job holds already when it is retried. One guarded update, so two workers never both run it.
  def claim!(by:)
    moved = self.class.where(id: id, status: LIVE_STATUSES)
                .where("lease_until IS NULL OR lease_until < :now OR lease_holder = :holder", now: Time.current, holder: by)
                .update_all(status: STATUS_RUNNING, lease_holder: by, lease_until: LEASE.from_now, attempts: Arel.sql("attempts + 1"),
                            started_at: Arel.sql("COALESCE(started_at, now())"), updated_at: Time.current) > 0
    return false unless moved

    reload
    announce!(CHANGE_STARTED)
    true
  end

  # Renewed between steps by the worker that holds it. False when another worker took it over, which stops this one.
  def renew_lease!(by:)
    self.class.where(id: id, status: STATUS_RUNNING, lease_holder: by).update_all(lease_until: LEASE.from_now, updated_at: Time.current) > 0
  end

  # Hands the review back so a retry can take it at once.
  def release!(by:)
    self.class.where(id: id, status: STATUS_RUNNING, lease_holder: by).update_all(lease_until: nil, updated_at: Time.current)
  end

  def finish!(status:, error_summary: nil)
    raise ArgumentError, "#{status} is not a terminal status" if LIVE_STATUSES.include?(status)

    moved = self.class.where(id: id, status: LIVE_STATUSES)
                .update_all(status: status, error_summary: error_summary, finished_at: Time.current, lease_until: nil, updated_at: Time.current) > 0
    return false unless moved

    reload
    announce!(status == STATUS_DONE ? CHANGE_FINISHED : CHANGE_FAILED)
    true
  end

  # What the review read and how risky it judged the change, saved once every part is reviewed.
  def concluded!(summary:, risk:, risk_reason:)
    update!(summary: summary, risk: risk, risk_reason: risk_reason)
  end

  # Learned from the code host when the pull request merged, which is when a fixed finding counts as prevented.
  def merged!(at)
    self.class.where(id: id, merged_at: nil).update_all(merged_at: at, updated_at: Time.current).positive?.tap { |moved| reload if moved }
  end

  def spent!(turns_used:, spent_micros:)
    update_columns(turns_used: turns_used, spent_micros: spent_micros, updated_at: Time.current)
  end

  # The next place in the review's order, for a finding about to be written.
  def next_position = (findings.maximum(:position) || 0) + 1
end
