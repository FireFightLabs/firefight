# A memory an incident taught is a lesson, and so is one a pull request Halon opened taught by how a person handled it.
# Pull request reviews check it only once the incident's lead, or whoever asked for the pull request, or a workspace
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

    scope :lessons, -> { where(source_type: Chat::Memory::Lesson.source_types) }
    # What reviews check: approved, and still in use, so one disputed or rejected since waits on a person again.
    scope :approved_lessons, -> { lessons.in_use.where.not(approved_at: nil) }

    # Deleting an approved lesson clears the findings it produced, so they are named before it goes.
    before_destroy -> { @held_finding_ids = held_finding_ids }, if: :approved?
    after_destroy_commit -> { announce_lesson_change(@held_finding_ids) }, if: :approved?
  end

  # What a lesson can come from: an incident, or a pull request Halon opened (its coding agent's session).
  def self.source_types = [ Incident.polymorphic_name, CodeAgentSession.polymorphic_name ]

  class_methods do
    # The open findings the given lessons produced on pull requests not merged yet.
    def held_finding_ids_of(lesson_ids)
      PullRequestReview::Finding.still_open.where(lesson_id: lesson_ids).joins(:review).where(pull_request_reviews: { merged_at: nil }).pluck(:id)
    end

    # Each finding changed with its lesson, once the change commits, so the pull request's check is worked out again
    # and its comments say where the lesson stands now. A change that rolls back is never said.
    def announce_findings_changed(finding_ids)
      return if finding_ids.blank?

      ActiveRecord.after_all_transactions_commit do
        PullRequestReview::Finding.where(id: finding_ids).includes(:review).each do |finding|
          finding.review.announce!(PullRequestReview::CHANGE_FINDING_CHANGED, finding: finding)
        end
      end
    end

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

  # The lesson a decision is asked about, as the gateway's scope names it.
  SCOPE_LESSON = "lesson".freeze

  class_methods do
    # An incident's lead decides on its lessons, and whoever asked Halon for a pull request on its lessons, without a grant.
    def decided_by_owner?(member, scope)
      id = scope.to_h.stringify_keys[SCOPE_LESSON]
      lesson = id.present? && lessons.where(workspace_id: member.workspace_id).find_by(id: id)
      lesson.present? && lesson.lesson_owner == member
    end
  end

  def decide_scope = { SCOPE_LESSON => id }

  # Who holds deciding on it without a grant, beside admins: the incident's lead, or whoever asked for the pull request.
  def lesson_owner = from_incident? ? source.lead : source.requester

  def from_incident? = source_type == Incident.polymorphic_name

  def from_pull_request? = source_type == CodeAgentSession.polymorphic_name

  def lesson? = from_incident? || from_pull_request?

  # Where it came from, as a lesson names it: "INC-052" or "PR #412".
  def lesson_origin = from_incident? ? source.identifier : source.lesson_origin

  # Where a person reads where it came from: the incident's page, or the pull request on its code host.
  def lesson_origin_url
    return AppUrl.absolute(Rails.application.routes.url_helpers.incident_path(source_id)) if from_incident?

    source.pull_request_url
  end

  # How the Lessons tab names where it came from, such as "INC-052 Checkout failing" or "PR #412 in acme/checkout".
  def lesson_origin_title = from_incident? ? "#{source.identifier} #{source.name}" : "#{source.lesson_origin} in #{source.repository}"

  def approved? = approved_at.present?

  # Checked in reviews now.
  def approved_lesson? = lesson? && approved? && in_use?

  def lesson_status
    return STATUS_TURNED_DOWN if state == Chat::Memory::STATE_REJECTED
    return STATUS_APPROVED if approved_lesson?

    STATUS_WAITING
  end

  # Who may approve, edit or turn down a lesson, as the gateway answers lessons.decide for it: an admin, the incident's
  # lead or whoever asked Halon for the pull request that taught it, or anyone granted it.
  def lesson_blocked_reason(member)
    return "Only lessons an incident or one of Halon's pull requests taught are approved for pull request reviews." unless lesson?

    action = Ability::Action.lookup(Ability::Action::LESSON_DECIDE, workspace)
    return nil if member && AbilityGateway.permitted?(member, action, Ability::Action::LESSON_DECIDE, workspace, decide_scope)

    if from_pull_request?
      return "Only whoever asked for #{source.lesson_origin} in #{source.repository}, a workspace admin or someone granted Decide on lessons " \
             "can decide on its lessons."
    end

    "Only the #{source.identifier} lead, a workspace admin or someone granted Decide on lessons can decide on its lessons."
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

  # Approval is the lesson's own and leaves how Halon trusts the memory as it was. Guarded on it still being in use and
  # not approved yet, so someone turning it down at the same moment wins and of two approvals only the first lands.
  # Returns whether this call approved it.
  def approve!(by:, strict: false)
    return false if approve_blocked_reason(by)

    approved = self.class.where(id: id, state: Chat::Memory::USED_STATES, approved_at: nil)
                         .update_all(approved_by_id: by.id, approved_at: Time.current, strict: strict, updated_at: Time.current) > 0
    reload
    announce_lesson_change if approved
    approved
  end

  # The lead or an admin rewording it. New words replace it as a lesson approved by them, and the old wording is kept as
  # rejected so it is not learned again. The same words only change whether it is strict. Returns the lesson that stands.
  def edit_lesson!(by:, text:, strict:)
    return nil if edit_lesson_blocked_reason(by)

    words = text.to_s.strip
    if words == self.text.strip
      return nil unless approved_lesson? || approve!(by: by, strict: strict)

      update!(strict: strict)
      announce_lesson_change
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

  def held_finding_ids = self.class.held_finding_ids_of([ id ])

  def announce_lesson_change(finding_ids = held_finding_ids) = self.class.announce_findings_changed(finding_ids)

  private

  def approve_state_blocked_reason
    return TURNED_DOWN_REASON if state == Chat::Memory::STATE_REJECTED
    return "It is approved already." if approved_lesson?
    return "Halon stopped using it, so reviews cannot check it. Settle it on the Memories tab first." unless in_use?

    nil
  end
end
