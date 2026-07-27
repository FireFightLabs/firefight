class IncidentType < ApplicationRecord
  include Positioned

  belongs_to :workspace
  has_many :incidents, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }
  validates :position, presence: true, numericality: { only_integer: true }
  validates :is_default, uniqueness: { scope: :workspace_id, if: :is_default? }

  scope :active, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:position) }
  scope :default_type, -> { active.find_by(is_default: true) }
  # One correlated subquery for the whole page instead of a count per row.
  scope :with_incident_counts, -> {
    select(
      "#{table_name}.*",
      "(SELECT COUNT(*) FROM incidents WHERE incidents.incident_type_id = #{table_name}.id) AS incidents_count"
    )
  }

  def enabled?
    deleted_at.nil?
  end

  def incident_count
    has_attribute?(:incidents_count) ? self[:incidents_count].to_i : incidents.count
  end

  def deletable?
    incident_count.zero?
  end

  def make_default!
    self.class.transaction do
      workspace.incident_types.where(is_default: true).where.not(id: id).update_all(is_default: false)
      update!(is_default: true)
    end
  end
end
