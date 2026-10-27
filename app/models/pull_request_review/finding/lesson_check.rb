# A finding a lesson produced names the lesson, such as "Lesson from INC-052". One from a lesson that is strict and
# still approved holds the pull request's check failing while it is open, until a person overrides it.
module PullRequestReview::Finding::LessonCheck
  extend ActiveSupport::Concern

  OVERRIDE_NEEDS_REASON = "Say why the pull request may go through anyway.".freeze
  # The finding an override is asked for, as the gateway's scope names it.
  SCOPE_FINDING = "finding".freeze

  included do
    belongs_to :lesson, class_name: "Chat::Memory", optional: true
    belongs_to :overridden_by, class_name: "WorkspaceMembership", optional: true

    before_create :keep_override

    # Open findings from lessons that are strict now, which nobody overrode.
    scope :holding, lambda {
      still_open.where(overridden_at: nil).joins(:lesson).merge(Chat::Memory.approved_lessons.where(strict: true))
    }
  end

  class_methods do
    # Whether member owns a service the pull request of the finding the scope names belongs to.
    def overrides_as_owner?(member, scope)
      id = scope.to_h.stringify_keys[SCOPE_FINDING]
      finding = id.present? && joins(:review).where(pull_request_reviews: { workspace_id: member.workspace_id }).find_by(id: id)
      finding.present? && finding.review.owned_by?(member)
    end

    # The same problem found again on a later head of a pull request counts once, as the Lessons tab lists it and the
    # check counts it.
    def once_per_problem(findings) = findings.uniq { |finding| [ finding.review.repository.downcase, finding.review.number, finding.fingerprint ] }

    # What the Lessons tab lists as held: each problem once, as its newest review found it.
    def held_on_pull_requests(workspace, lessons) = once_per_problem(from_strict_lessons(workspace, lessons).to_a)

    # Open findings from lessons that are strict now on pull requests not merged yet, overridden or not, newest first.
    # lessons is the memories the reader may see.
    def from_strict_lessons(workspace, lessons)
      still_open.joins(:review).merge(PullRequestReview.seen).where(pull_request_reviews: { workspace_id: workspace.id, merged_at: nil })
          .where(lesson_id: lessons.approved_lessons.where(strict: true).select(:id))
          .preload(:overridden_by, :review, lesson: :source).order(created_at: :desc)
    end
  end

  # The same problem found again on a later head of the same pull request stays overridden, so a person is not asked twice.
  def keep_override
    return if lesson_id.nil? || review.nil?

    earlier = PullRequestReview::Finding.where(pull_request_review_id: review.reviews_of_pull_request.where.not(id: review.id).select(:id),
                                               fingerprint: fingerprint).where.not(overridden_at: nil).order(:overridden_at).last
    self.overridden_by_id, self.overridden_at, self.override_reason = earlier.overridden_by_id, earlier.overridden_at, earlier.override_reason if earlier
  end

  # Whether its lesson is one a review fails a check on, now.
  def strict? = lesson.present? && lesson.approved_lesson? && lesson.strict

  def holding? = strict? && open? && overridden_at.nil?

  def overridden? = overridden_at.present?

  # "Lesson from INC-052" or "Lesson from PR #412", the line a comment names its lesson with.
  def lesson_label = (lesson&.lesson? ? "Lesson from #{lesson.lesson_origin}" : nil)

  def override_scope = { SCOPE_FINDING => id }

  # Why member may not override it, or nil once they may: an admin, an owner of a service the pull request belongs to,
  # or anyone granted the override, as the gateway answers. Then what the finding itself allows.
  def override_blocked_reason(member)
    override_denied_reason(member) || override_state_blocked_reason
  end

  def override_denied_reason(member)
    action = Ability::Action.lookup(Ability::Action::LESSON_OVERRIDE, review.workspace)
    return nil if member && AbilityGateway.permitted?(member, action, Ability::Action::LESSON_OVERRIDE, review.workspace, override_scope)

    "Only a workspace admin, an owner of a service #{review.repository} belongs to, or someone granted Override strict lessons can override it."
  end

  def override_state_blocked_reason
    return "Only a finding from a strict lesson holds a check." unless strict?
    return "It is fixed already." if fixed?
    return "It was withdrawn." if withdrawn?
    return "#{overridden_by&.display_name || 'Someone'} overrode it already." if overridden?

    nil
  end

  # A person letting the pull request through although the finding stands, saying why. Guarded, so two people
  # overriding at once land once. Returns whether it is overridden now.
  def override!(by:, reason:)
    return false if override_state_blocked_reason || reason.blank?

    moved = self.class.where(id: id, status: PullRequestReview::Finding::STATUS_OPEN, overridden_at: nil)
                .update_all(overridden_by_id: by.id, overridden_at: Time.current, override_reason: reason, updated_at: Time.current) > 0
    reload
    return false unless moved

    review.announce!(PullRequestReview::CHANGE_FINDING_CHANGED, finding: self)
    true
  end
end
