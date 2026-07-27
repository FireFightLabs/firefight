# Shared behaviour for the workspace-configurable option lists a settings screen
# manages: severities, statuses, incident types. Each is positioned, soft
# disableable, has exactly one default, and refuses deletion while incidents
# point at it.
#
# The *_blocked_reason methods are the single source of truth for those rules.
# The controller turns a reason into a flash alert, the serializer ships it, and
# the row renders it as a tooltip, so a rule is written once rather than once
# per layer.
module ConfigurableOption
  extend ActiveSupport::Concern

  included do
    include Positioned

    belongs_to :workspace
    has_many :incidents, dependent: :restrict_with_error

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: { scope: :workspace_id }
    validates :position, presence: true, numericality: { only_integer: true }
    validates :is_default, uniqueness: { scope: :workspace_id, if: :is_default? }

    scope :active, -> { where(deleted_at: nil) }
    scope :ordered, -> { order(:position) }
  end

  class_methods do
    # One correlated subquery for the page rather than a count per row.
    def with_incident_counts
      select(
        "#{table_name}.*",
        "(SELECT COUNT(*) FROM incidents WHERE incidents.#{incidents_foreign_key} = #{table_name}.id) AS incidents_count"
      )
    end

    def incidents_foreign_key
      reflect_on_association(:incidents).foreign_key
    end
  end

  def enabled?
    deleted_at.nil?
  end

  # Reads the count attached by with_incident_counts, falling back to a query so
  # a caller that forgot the scope gets a correct answer, not a permissive one.
  def incident_count
    has_attribute?(:incidents_count) ? self[:incidents_count].to_i : incidents.count
  end

  # Exactly one default per workspace, so promoting one demotes the incumbent in
  # the same transaction. A partial unique index backs this up, since the model
  # validation alone cannot stop an update_all or a raw write.
  def make_default!
    self.class.transaction do
      self.class.where(workspace_id: workspace_id, is_default: true).where.not(id: id).update_all(is_default: false)
      update!(is_default: true)
    end
  end

  def deletion_blocked_reason
    return "#{name} is the default #{noun}. Make another #{noun} the default before deleting it." if is_default?

    if incident_count.positive?
      return "#{name} is in use by #{incident_count} #{'incident'.pluralize(incident_count)} and cannot be deleted. " \
             "Disable it instead."
    end

    nil
  end

  def disable_blocked_reason
    return unless is_default?

    "#{name} is the default #{noun} and has to stay enabled. Make another #{noun} the default first."
  end

  def default_blocked_reason
    return if enabled?

    "#{name} is disabled. Enable it before making it the default."
  end

  private

  def noun
    self.class::NOUN
  end
end
