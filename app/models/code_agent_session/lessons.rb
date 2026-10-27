# How a person treated a pull request Halon opened, kept once it merged or closed, so the cause can become a lesson for
# its repository. One merged as Halon wrote it was accepted and teaches nothing. One a person changed before merging,
# or closed, is recorded with what they wrote and changed, and read once, however often the host says it ended.
module CodeAgentSession::Lessons
  extend ActiveSupport::Concern

  # The author the coding agent's sandbox gives Halon's commits, which tells them apart from a person's.
  COMMIT_EMAIL = "halon@firefight.invalid".freeze
  OUTCOME_EDITED = "edited".freeze
  OUTCOME_CLOSED = "closed".freeze
  # How many earlier pull requests in the same repository a lesson is read against.
  EARLIER_SHOWN = 10

  included do
    scope :handled_by_people, -> { where.not(pull_request_outcome: nil) }
  end

  class_methods do
    # Earlier pull requests Halon opened in repository that a person changed or closed, newest first.
    def handled_before(session)
      handled_by_people.where(workspace_id: session.workspace_id).where("lower(repository) = ?", session.repository.downcase)
                       .where.not(id: session.id).order(pull_request_ended_at: :desc, created_at: :desc).limit(EARLIER_SHOWN).to_a
    end
  end

  # "PR #412 in acme/checkout", how a lesson it taught says where it came from.
  def lesson_origin = "PR ##{pull_request_number}"

  # Takes the ended pull request for one read. False when it was read already.
  def claim_lesson_read!
    self.class.where(id: id, pull_request_lesson_read_at: nil).update_all(pull_request_lesson_read_at: Time.current, updated_at: Time.current) == 1
  end

  # Gives the read back, such as when the host says it has not ended after all.
  def release_lesson_read! = self.class.where(id: id).update_all(pull_request_lesson_read_at: nil, updated_at: Time.current)

  def handled!(kind, person:, summary:)
    update_columns(pull_request_outcome: { "kind" => kind, "person" => person, "summary" => summary.to_s.truncate(1_000) },
                   pull_request_ended_at: pull_request_ended_at || Time.current, updated_at: Time.current)
  end

  def outcome_kind = pull_request_outcome&.dig("kind")

  def outcome_summary = pull_request_outcome&.dig("summary")

  # What a lesson it taught is about: the repository on the map, or the service that owns it in the catalog, or the
  # whole workspace when neither holds it.
  def lesson_subject
    ResourceMap::Resource.present.where(workspace_id: workspace_id, kind: ResourceMap::KIND_REPOSITORY)
                         .where("lower(external_id) = ?", repository.downcase).order(:created_at).first ||
      CatalogEntry.owning_repository(workspace, repository).first
  end

  # The member who asked for the change, who may decide on the lessons its pull request taught.
  def requester = (principal if principal.is_a?(WorkspaceMembership))
end
