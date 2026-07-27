class IncidentStatus < ApplicationRecord
  include Positioned

  belongs_to :workspace
  belongs_to :incident_lifecycle_stage

  has_many :incidents, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }
  validates :position, presence: true, numericality: { only_integer: true }
  validates :is_default, uniqueness: { scope: :workspace_id, if: :is_default? }

  scope :active, -> { where(deleted_at: nil) }
  scope :triage, -> { joins(:incident_lifecycle_stage).where(incident_lifecycle_stages: { key: IncidentLifecycleStage::TRIAGE }) }
  scope :live, -> { joins(:incident_lifecycle_stage).where(incident_lifecycle_stages: { key: [ IncidentLifecycleStage::TRIAGE, IncidentLifecycleStage::ACTIVE ] }) }
  scope :closed, -> { joins(:incident_lifecycle_stage).where(incident_lifecycle_stages: { key: IncidentLifecycleStage::CLOSED }) }
  scope :canceled, -> { joins(:incident_lifecycle_stage).where(incident_lifecycle_stages: { key: IncidentLifecycleStage::CANCELED }) }
  scope :ordered, -> { order(:position) }
  scope :default_status, -> { active.find_by(is_default: true) }
  # One correlated subquery for the whole page instead of an exists? per row.
  scope :with_incident_counts, -> {
    select(
      "#{table_name}.*",
      "(SELECT COUNT(*) FROM incidents WHERE incidents.incident_status_id = #{table_name}.id) AS incidents_count"
    )
  }

  delegate :triage?, :active?, :closed?, :canceled?, to: :incident_lifecycle_stage

  def live?
    triage? || active?
  end

  def enabled?
    deleted_at.nil?
  end

  def incident_count
    has_attribute?(:incidents_count) ? self[:incidents_count].to_i : incidents.count
  end

  def deletable?
    incident_count.zero? && !last_enabled_in_stage?
  end

  # Every stage has to keep at least one usable status. Emptying one strands
  # any incident that reaches that stage with nothing to move into.
  def last_enabled_in_stage?
    return false unless enabled?

    workspace.incident_statuses
      .active
      .where(incident_lifecycle_stage_id: incident_lifecycle_stage_id)
      .where.not(id: id)
      .none?
  end

  # The default is where a newly declared incident starts, so it has to be a
  # stage an incident can actually open in.
  def defaultable?
    enabled? && live?
  end

  def make_default!
    self.class.transaction do
      workspace.incident_statuses.where(is_default: true).where.not(id: id).update_all(is_default: false)
      update!(is_default: true)
    end
  end

  # Statuses are grouped by stage in the UI but share one position sequence, so
  # a drag inside a stage renumbers the workspace with the other stages held put.
  def self.reorder_within_stage!(workspace, stage_key, ordered_ids)
    by_stage = workspace.incident_statuses.ordered.includes(:incident_lifecycle_stage)
      .group_by { |status| status.incident_lifecycle_stage.key }

    final = IncidentLifecycleStage.ordered.flat_map do |stage|
      ids = (by_stage[stage.key] || []).map(&:id)
      next ids unless stage.key == stage_key

      requested = ordered_ids.map(&:to_s).select { |id| ids.include?(id) }
      requested + (ids - requested)
    end

    reorder!(workspace, final)
  end
end
