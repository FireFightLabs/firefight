# A finding a lesson produced names the lesson, such as "Lesson from INC-052". One from a lesson that is strict and
# still approved holds the pull request's check failing while it is open, until a person overrides it.
module PullRequestReview::Finding::LessonCheck
  extend ActiveSupport::Concern

  OVERRIDE_NEEDS_REASON = "Say why the pull request may go through anyway.".freeze

  included do
    belongs_to :lesson, class_name: "Chat::Memory", optional: true
    belongs_to :overridden_by, class_name: "WorkspaceMembership", optional: true

    # Open findings from lessons that are strict now, which nobody overrode.
    scope :holding, lambda {
      still_open.where(overridden_at: nil).joins(:lesson).merge(Chat::Memory.approved_lessons.where(strict: true))
    }
  end

  class_methods do
    # Open findings from lessons that are strict now on pull requests not merged yet, overridden or not, newest first.
    # lessons is the memories the reader may see.
    def from_strict_lessons(workspace, lessons)
      still_open.joins(:review).merge(PullRequestReview.seen).where(pull_request_reviews: { workspace_id: workspace.id, merged_at: nil })
          .where(lesson_id: lessons.approved_lessons.where(strict: true).select(:id))
          .preload(:overridden_by, :review, lesson: :source).order(created_at: :desc)
    end
  end

  # Whether its lesson is one a review fails a check on, now.
  def strict? = lesson.present? && lesson.approved_lesson? && lesson.strict

  def holding? = strict? && open? && overridden_at.nil?

  def overridden? = overridden_at.present?

  # "Lesson from INC-052", the line a comment names its lesson with.
  def lesson_label = (lesson&.from_incident? ? "Lesson from #{lesson.source.identifier}" : nil)

  def override_blocked_reason
    return "Only a finding from a strict lesson holds a check." unless strict?
    return "It is fixed already." if fixed?
    return "It was withdrawn." if withdrawn?
    return "#{overridden_by&.display_name || 'Someone'} overrode it already." if overridden?

    nil
  end

  # A person letting the pull request through although the finding stands, saying why. Guarded, so two people
  # overriding at once land once. Returns whether it is overridden now.
  def override!(by:, reason:)
    return false if override_blocked_reason || reason.blank?

    moved = self.class.where(id: id, status: PullRequestReview::Finding::STATUS_OPEN, overridden_at: nil)
                .update_all(overridden_by_id: by.id, overridden_at: Time.current, override_reason: reason, updated_at: Time.current) > 0
    return false unless moved

    reload
    review.announce!(PullRequestReview::CHANGE_FINDING_CHANGED, finding: self)
    true
  end
end
