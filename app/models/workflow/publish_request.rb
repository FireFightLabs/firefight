# A member who built or changed a workflow asks the workspace admins to publish it, the way a member asks for a pack:
# one row per member and workflow, asking is a click, and the admins hear at most once a day for the same member and
# workflow however often it is pressed. Publishing the workflow from anywhere settles it.
class Workflow::PublishRequest < ApplicationRecord
  self.table_name = "workflow_publish_requests"

  include Workflow::LiveSignal

  shown_on_workflow_page PART_CANVAS

  WINDOW = Ability::PackRequest::WINDOW

  belongs_to :workspace
  belongs_to :workflow, inverse_of: :publish_requests
  # The draft they asked about, and its revision when the admins were asked (revision), which is what Publish publishes.
  belongs_to :version, class_name: "Workflow::Version"
  belongs_to :requester, class_name: "WorkspaceMembership"
  belongs_to :published_by, class_name: "WorkspaceMembership", optional: true

  validates :requester_id, uniqueness: { scope: :workflow_id }

  # Asked, and still waiting on an admin.
  scope :waiting, -> { where.not(requested_at: nil).where(published_at: nil, dismissed_at: nil) }

  def self.for!(requester, workflow, version)
    request = find_or_create_by!(workspace_id: workflow.workspace_id, workflow: workflow, requester: requester) { |made| made.version = version }
    unless request.version_id == version.id
      request.update_columns(version_id: version.id, updated_at: Time.current)
      request.signal_workflow_page
    end
    request
  rescue ActiveRecord::RecordNotUnique
    find_by!(workflow: workflow, requester: requester)
  end

  # Claims the ask in one statement, so two clicks at once send one message. False when the admins were told within the
  # window and have not answered since.
  def claim_ask!
    won = self.class.where(id: id)
              .where("requested_at IS NULL OR requested_at < :since OR published_at IS NOT NULL OR dismissed_at IS NOT NULL", since: WINDOW.ago)
              .update_all(requested_at: Time.current, revision: version.reload.revision, published_at: nil, published_by_id: nil, dismissed_at: nil,
                          notifications: [], updated_at: Time.current)
    signal_workflow_page
    reload
    won == 1
  end

  # by is who would press Ask an admin to publish.
  def ask_blocked_reason(by = requester)
    return "Only #{requester.display_name} can ask for this, since they asked first." unless by == requester
    return "#{workflow.name} has no draft to publish." unless version&.draft?
    return unless waiting? && requested_at > WINDOW.ago

    "You asked the admins at #{requested_at.utc.strftime('%H:%M UTC')}, so they are not asked again until a day has passed."
  end

  # Settled by whoever published the workflow, in one statement, so the member is told once. True only for that one.
  def published!(by:)
    won = self.class.where(id: id, published_at: nil, dismissed_at: nil).update_all(published_at: Time.current, published_by_id: by&.id, updated_at: Time.current)
    signal_workflow_page
    reload
    won == 1
  end

  def dismiss!(by:)
    won = self.class.where(id: id, published_at: nil, dismissed_at: nil).update_all(dismissed_at: Time.current, published_by_id: by.id, updated_at: Time.current)
    signal_workflow_page
    reload
    won == 1
  end

  def waiting? = requested_at.present? && published_at.nil? && dismissed_at.nil?

  # Why Publish on this request cannot publish the draft as it is now, because it changed since the admins were asked.
  def stale_reason(draft)
    return if draft.id == version_id && draft.revision == revision

    "#{workflow.name} changed since #{requester.display_name} asked, so open it and look again before publishing."
  end

  def answered_by_name = published_by&.display_name || "An admin"

  def add_notification!(channel_id:, message_id:)
    self.class.where(id: id).update_all([ "notifications = notifications || ?::jsonb", [ { channel_id: channel_id, message_id: message_id } ].to_json ])
  end
end
