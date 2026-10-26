# A memory an incident taught is a lesson. Pull request reviews check it only once the incident's lead or a workspace
# admin approves it, and that person can edit it or turn it down instead. Most lessons comment on a pull request that
# goes against them, and a strict one also fails a check on it until the finding is fixed or someone overrides it.
module Chat::Memory::Lesson
  extend ActiveSupport::Concern

  TURNED_DOWN = "Turned down".freeze
  TURNED_DOWN_REASON = "It was turned down. Add it again on the Memories tab if it is right after all.".freeze
  # Where a lesson stands for reviews. Waiting covers one never approved and one approved that is disputed, outdated or
  # expired since, which waits on a person again.
  STATUS_WAITING = "waiting".freeze
  STATUS_APPROVED = "approved".freeze
  STATUS_TURNED_DOWN = "turned_down".freeze
  STATUSES = [ STATUS_WAITING, STATUS_APPROVED, STATUS_TURNED_DOWN ].freeze
  # How many approved lessons one review reads, those about what the change touches first.
  REVIEW_LIMIT = 40

  included do
    belongs_to :approved_by, class_name: "WorkspaceMembership", optional: true

    scope :lessons, -> { where(source_type: Incident.polymorphic_name) }
    # What reviews check: approved, and still in use, so one disputed or rejected since waits on a person again.
    scope :approved_lessons, -> { lessons.in_use.where.not(approved_at: nil) }
  end

  class_methods do
    # The approved lessons a review of a change checks: those about the given subjects, such as the services that own
    # the repository and the resources they run on, then those about the whole workspace, then the rest, newest first.
    def for_review(workspace, subjects)
      approved = approved_lessons.where(workspace: workspace).includes(:subject, :source)
      about = subjects.compact.group_by { |subject| subject.class.name }.map { |type, found| approved.where(subject_type: type, subject_id: found.map(&:id)) }
      touching = about.inject(approved.none) { |union, part| union.or(part) }.order(approved_at: :desc).to_a
      wide = approved.where(subject_id: nil).order(approved_at: :desc).to_a
      rest = approved.where.not(id: (touching + wide).map(&:id)).order(approved_at: :desc).limit(REVIEW_LIMIT).to_a
      (touching + wide + rest).uniq.first(REVIEW_LIMIT)
    end
  end

  def from_incident? = source_type == Incident.polymorphic_name

  def approved? = approved_at.present?

  # Checked in reviews now.
  def approved_lesson? = from_incident? && approved? && in_use?

  def lesson_status
    return STATUS_TURNED_DOWN if state == Chat::Memory::STATE_REJECTED
    return STATUS_APPROVED if approved_lesson?

    STATUS_WAITING
  end

  # Who may approve, edit or turn down an incident's lessons: its lead, or a workspace admin.
  def lesson_blocked_reason(member)
    return "Only lessons an incident taught are approved for pull request reviews." unless from_incident?
    return nil if member&.admin_access? || (member && source.lead == member)

    "Only the #{source.identifier} lead or a workspace admin can decide on its lessons."
  end

  def approve_blocked_reason(member)
    lesson_blocked_reason(member) || approve_state_blocked_reason
  end

  def edit_lesson_blocked_reason(member)
    lesson_blocked_reason(member) || (TURNED_DOWN_REASON if state == Chat::Memory::STATE_REJECTED)
  end

  def turn_down_blocked_reason(member)
    lesson_blocked_reason(member) || reject_blocked_reason
  end

  # Approving vouches for it as well, so a lesson waiting on a person is confirmed by them too. Guarded on it still
  # being confirmed, so someone turning it down at the same moment wins. Returns whether it is approved now.
  def approve!(by:, strict: false)
    return false if approve_blocked_reason(by)

    transaction do
      confirm!(by: by) unless confirmed?
      approved = self.class.where(id: id, state: Chat::Memory::STATE_CONFIRMED)
                           .update_all(approved_by_id: by.id, approved_at: Time.current, strict: strict, updated_at: Time.current) > 0
      reload
      approved
    end
  end

  # The lead or an admin rewording it. New words replace it as a lesson approved by them, and the old wording is kept as
  # rejected so it is not learned again. The same words only change whether it is strict. Returns the lesson that stands.
  def edit_lesson!(by:, text:, strict:)
    return nil if edit_lesson_blocked_reason(by)

    words = text.to_s.strip
    if words == self.text.strip
      approve!(by: by, strict: strict) unless approved_lesson?
      update!(strict: strict)
      return self
    end

    transaction do
      replacement = reject!(by: by, reason: "Edited by #{by.display_name}", correction: words)
      replacement&.approve!(by: by, strict: strict)
      replacement
    end
  end

  # Turned down by the lead or an admin: rejected, so neither reviews nor Halon use it, and it is not learned again.
  def turn_down!(by:, reason: nil)
    return nil if turn_down_blocked_reason(by)

    reject!(by: by, reason: reason.presence || "#{TURNED_DOWN} by #{by.display_name}")
  end

  # A person confirming it from a channel or the Memory page. The lead or an admin confirming a lesson approves it, so it
  # is checked in reviews from then on. Anyone else confirms it as before.
  def confirm_or_approve!(by:)
    return confirm!(by: by) if lesson_blocked_reason(by)

    approve!(by: by, strict: strict)
  end

  # A person correcting it from a channel or the Memory page. The correction is a lesson approved by the lead or an
  # admin who wrote it, and keeps whether the lesson was strict.
  def correct!(by:, reason:, correction:)
    transaction do
      replacement = reject!(by: by, reason: reason, correction: correction)
      replacement.approve!(by: by, strict: strict) if replacement && replacement.from_incident? && replacement.lesson_blocked_reason(by).nil?
      replacement
    end
  end

  private

  def approve_state_blocked_reason
    return TURNED_DOWN_REASON if state == Chat::Memory::STATE_REJECTED
    return "It is approved already." if approved_lesson?

    nil
  end
end
