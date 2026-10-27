# One problem a review found in a pull request, written only once a separate check showed it holds. Each leads with its
# category, severity and effort, a one line claim and why, carries the chain from the change to the failure with the
# evidence behind each link, and a fix with instructions a coding agent can follow. A later finding can confirm,
# strengthen or withdraw it, and a push can fix it.
class PullRequestReview::Finding < ApplicationRecord
  include PullRequestReview::Finding::Threading

  CATEGORY_CORRECTNESS = "correctness"
  CATEGORY_STABILITY = "stability"
  CATEGORY_SECURITY = "security"
  CATEGORY_DATA_INTEGRITY = "data_integrity"
  CATEGORY_MAINTAINABILITY = "maintainability"
  CATEGORY_PERFORMANCE = "performance"
  CATEGORY_LABELS = {
    CATEGORY_CORRECTNESS => "Functional Correctness", CATEGORY_STABILITY => "Stability & Availability",
    CATEGORY_SECURITY => "Security & Privacy", CATEGORY_DATA_INTEGRITY => "Data Integrity & Integration",
    CATEGORY_MAINTAINABILITY => "Maintainability & Code Quality", CATEGORY_PERFORMANCE => "Performance & Scalability"
  }.freeze
  CATEGORIES = CATEGORY_LABELS.keys.freeze

  SEVERITY_CRITICAL = "critical"
  SEVERITY_MAJOR = "major"
  SEVERITY_MINOR = "minor"
  SEVERITY_TRIVIAL = "trivial"
  SEVERITIES = [ SEVERITY_CRITICAL, SEVERITY_MAJOR, SEVERITY_MINOR, SEVERITY_TRIVIAL ].freeze
  # What counts toward the problems a review prevented, beside a finding marked serious.
  PREVENTING_SEVERITIES = [ SEVERITY_CRITICAL, SEVERITY_MAJOR ].freeze

  EFFORT_QUICK_WIN = "quick_win"
  EFFORT_HEAVY_LIFT = "heavy_lift"
  EFFORT_LOW_VALUE = "low_value"
  EFFORT_LABELS = { EFFORT_QUICK_WIN => "Quick win", EFFORT_HEAVY_LIFT => "Heavy lift", EFFORT_LOW_VALUE => "Low value" }.freeze
  EFFORTS = EFFORT_LABELS.keys.freeze

  STATUS_OPEN = "open"
  STATUS_FIXED = "fixed"
  STATUS_WITHDRAWN = "withdrawn"
  STATUSES = [ STATUS_OPEN, STATUS_FIXED, STATUS_WITHDRAWN ].freeze

  # What a piece of evidence points at.
  EVIDENCE_INCIDENT = "incident"
  EVIDENCE_POSTMORTEM = "postmortem"
  EVIDENCE_MAP_RESOURCE = "map_resource"
  EVIDENCE_METRIC = "metric"
  EVIDENCE_CODE = "code"
  EVIDENCE_KINDS = [ EVIDENCE_INCIDENT, EVIDENCE_POSTMORTEM, EVIDENCE_MAP_RESOURCE, EVIDENCE_METRIC, EVIDENCE_CODE ].freeze

  # What a later finding's check said of this one.
  CROSS_CHECK_CONFIRMED = "confirmed"
  CROSS_CHECK_STRENGTHENED = "strengthened"
  CROSS_CHECK_WITHDRAWN = "withdrawn"
  CROSS_CHECKS = [ CROSS_CHECK_CONFIRMED, CROSS_CHECK_STRENGTHENED, CROSS_CHECK_WITHDRAWN ].freeze

  # One piece of evidence: what it is, its title as people read it and where to open it.
  Evidence = Data.define(:kind, :title, :url) do
    def to_h = { "kind" => kind, "title" => title, "url" => url }
  end

  belongs_to :review, class_name: "PullRequestReview", foreign_key: :pull_request_review_id, inverse_of: :findings

  validates :fingerprint, :claim, :why, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :severity, inclusion: { in: SEVERITIES }
  validates :effort, inclusion: { in: EFFORTS }
  validates :status, inclusion: { in: STATUSES }
  validates :line, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :evidence_shaped

  after_create_commit -> { review.announce!(PullRequestReview::CHANGE_FINDING_ADDED, finding: self) }
  after_update_commit -> { review.announce!(withdrawn? ? PullRequestReview::CHANGE_FINDING_WITHDRAWN : PullRequestReview::CHANGE_FINDING_CHANGED, finding: self) }

  scope :still_open, -> { where(status: STATUS_OPEN) }
  scope :standing, -> { where.not(status: STATUS_WITHDRAWN) }
  # Serious, or major or worse, and fixed before its pull request merged, in a review people see.
  scope :prevented, lambda {
    joins(:review).merge(PullRequestReview.seen).where(status: STATUS_FIXED)
                  .where("pull_request_review_findings.serious OR pull_request_review_findings.severity IN (?)", PREVENTING_SEVERITIES)
                  .where.not(pull_request_reviews: { merged_at: nil })
                  .where("pull_request_review_findings.fixed_at <= pull_request_reviews.merged_at")
  }

  # The same problem in the same place, whatever words a run used for it, so a review run again finds its own finding.
  def self.fingerprint_for(path:, category:, claim:)
    Digest::SHA256.hexdigest([ path.to_s, category.to_s, claim.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish ].join("\u0000"))[0, 32]
  end

  def open? = status == STATUS_OPEN

  def fixed? = status == STATUS_FIXED

  def withdrawn? = status == STATUS_WITHDRAWN

  def category_label = CATEGORY_LABELS.fetch(category)

  def severity_label = severity.capitalize

  def effort_label = EFFORT_LABELS.fetch(effort)

  # "Stability & Availability | Major | Quick win", the line a comment leads with.
  def header = [ category_label, severity_label, effort_label ].join(" | ")

  def evidence_items = evidence.map { |item| Evidence.new(kind: item["kind"], title: item["title"], url: item["url"]) }

  # Fixed by a later commit. One guarded update, so a second check of the same push changes nothing.
  def fixed!(sha, at: Time.current)
    moved = self.class.where(id: id, status: STATUS_OPEN).update_all(status: STATUS_FIXED, fixed_in_sha: sha, fixed_at: at, updated_at: Time.current) > 0
    return false unless moved

    reload
    review.announce!(PullRequestReview::CHANGE_FINDING_CHANGED, finding: self)
    true
  end

  # Withdrawn because it does not hold after all, saying why. A fixed finding stays fixed.
  def withdraw!(reason, by: nil)
    moved = self.class.where(id: id, status: STATUS_OPEN)
                .update_all([ "status = ?, withdrawn_reason = ?, cross_checks = cross_checks || ?::jsonb, updated_at = ?",
                              STATUS_WITHDRAWN, reason, [ cross_check(CROSS_CHECK_WITHDRAWN, reason, by) ].to_json, Time.current ]) > 0
    return false unless moved

    reload
    review.announce!(PullRequestReview::CHANGE_FINDING_WITHDRAWN, finding: self)
    true
  end

  # A later finding's check showed this one holds. note is what it showed.
  def confirmed!(note, by:) = cross_checked!(CROSS_CHECK_CONFIRMED, note, by)

  # A later finding's check made this one worse or better shown. changes are the fields it rewrote, such as severity.
  def strengthened!(note, by:, **changes) = cross_checked!(CROSS_CHECK_STRENGTHENED, note, by, **changes)

  private

  # The check is appended in SQL, so one written meanwhile by another worker, such as a withdrawal, is kept. changes are
  # validated before they are written.
  def cross_checked!(outcome, note, by, **changes)
    assign_attributes(changes)
    validate!
    self.class.transaction do
      self.class.where(id: id).update_all([ "cross_checks = cross_checks || ?::jsonb", [ cross_check(outcome, note, by) ].to_json ])
      self.class.where(id: id).update_all(changes.merge(updated_at: Time.current))
    end
    reload
    review.announce!(PullRequestReview::CHANGE_FINDING_CHANGED, finding: self)
    true
  end

  def cross_check(outcome, note, by) = { "outcome" => outcome, "note" => note, "finding_id" => by&.id, "at" => Time.current.iso8601 }

  def evidence_shaped
    valid = evidence.is_a?(Array) && evidence.all? { |item| item.is_a?(Hash) && EVIDENCE_KINDS.include?(item["kind"]) && item["title"].present? }
    errors.add(:evidence, "must be a list of kind, title and url") unless valid
    errors.add(:failure_chain, "must be a list of steps") unless failure_chain.is_a?(Array) && failure_chain.all?(String)
  end
end
