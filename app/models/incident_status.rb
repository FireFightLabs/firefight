class IncidentStatus < ApplicationRecord
  include ConfigurableOption
  include DefaultableOption

  has_many :incidents, dependent: :restrict_with_error

  NOUN = "status".freeze

  belongs_to :incident_lifecycle_stage

  scope :triage, -> { joins(:incident_lifecycle_stage).where(incident_lifecycle_stages: { key: IncidentLifecycleStage::TRIAGE }) }
  scope :live, -> { joins(:incident_lifecycle_stage).where(incident_lifecycle_stages: { key: [ IncidentLifecycleStage::TRIAGE, IncidentLifecycleStage::ACTIVE ] }) }
  scope :closed, -> { joins(:incident_lifecycle_stage).where(incident_lifecycle_stages: { key: IncidentLifecycleStage::CLOSED }) }
  scope :canceled, -> { joins(:incident_lifecycle_stage).where(incident_lifecycle_stages: { key: IncidentLifecycleStage::CANCELED }) }
  scope :terminal, -> { joins(:incident_lifecycle_stage).where(incident_lifecycle_stages: { key: [ IncidentLifecycleStage::CLOSED, IncidentLifecycleStage::CANCELED ] }) }
  scope :default_status, -> { active.find_by(is_default: true) }

  delegate :triage?, :active?, :closed?, :canceled?, to: :incident_lifecycle_stage
  delegate :name, to: :incident_lifecycle_stage, prefix: :stage

  def self.with_usage_counts
    super.select(
      "(SELECT COUNT(*) FROM #{table_name} siblings" \
      " WHERE siblings.workspace_id = #{table_name}.workspace_id" \
      " AND siblings.incident_lifecycle_stage_id = #{table_name}.incident_lifecycle_stage_id" \
      " AND siblings.deleted_at IS NULL" \
      " AND siblings.id <> #{table_name}.id) AS enabled_siblings_count"
    )
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

  def live?
    triage? || active?
  end

  # Every stage has to keep at least one usable status, or an incident reaching
  # that stage has nothing to move into.
  def last_enabled_in_stage?
    return false unless enabled?

    enabled_siblings_count.zero?
  end

  def deletion_blocked_reason
    super || stage_floor_reason("deleting")
  end

  def disable_blocked_reason
    super || stage_floor_reason("disabling")
  end

  def default_blocked_reason
    return super if super
    return if live?

    "#{name} is a #{stage_name} status. A new incident has to start in triage or active."
  end

  private

  def enabled_siblings_count
    return self[:enabled_siblings_count].to_i if has_attribute?(:enabled_siblings_count)

    self.class.where(workspace_id: workspace_id, incident_lifecycle_stage_id: incident_lifecycle_stage_id)
      .active.where.not(id: id).count
  end

  def stage_floor_reason(verb)
    return unless last_enabled_in_stage?

    "#{name} is the only enabled status in #{stage_name}. Add another one before #{verb} it."
  end
end
