# One version in the canvas's history: its number and status, who made it and why, who published it, and each change
# that landed on it with who made it.
class WorkflowVersionRowSerializer < BaseSerializer
  object_as :version

  type :string
  def id
    version.id
  end

  type :number
  def number
    version.number
  end

  type "#{Workflow::Version::STATUSES.map(&:inspect).join(' | ')}"
  def status
    version.status
  end

  type :string
  def author_name
    version.by_halon? ? "Halon" : (version.author&.actor_display_name || "Someone")
  end

  type :boolean
  def by_halon
    version.by_halon?
  end

  type :string, optional: true
  def reason
    version.reason
  end

  type :string
  def created_at
    version.created_at.iso8601
  end

  type :string, optional: true
  def published_at
    version.published_at&.iso8601
  end

  type :string, optional: true
  def published_by_name
    version.published_by&.actor_display_name
  end

  type :string, optional: true
  def restore_blocked_reason
    version.restore_blocked_reason
  end

  has_many :edits, serializer: WorkflowEditLineSerializer do
    version.landed_edits.includes(:author, :decided_by).reverse
  end
end
