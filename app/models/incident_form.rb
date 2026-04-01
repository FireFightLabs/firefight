class IncidentForm < ApplicationRecord
  SLUG_DECLARE = "declare"
  SLUG_ACCEPT = "accept"
  SLUG_UPDATE = "update"
  SLUG_RESOLVE = "resolve"
  SLUGS = [ SLUG_DECLARE, SLUG_ACCEPT, SLUG_UPDATE, SLUG_RESOLVE ].freeze

  belongs_to :workspace

  has_many :incident_form_fields, -> { order(:position, :created_at) }, dependent: :destroy

  validates :slug, presence: true, uniqueness: { scope: :workspace_id }
  validates :name, presence: true
  validates :lifecycle_event, presence: true, inclusion: { in: SLUGS }
  validates :position, presence: true

  validate :slug_immutable, on: :update

  scope :ordered, -> { order(:position, :created_at) }

  def protected_form?
    SLUGS.include?(slug)
  end

  private

  def slug_immutable
    return unless slug_changed?

    errors.add(:slug, "cannot be changed after creation")
  end
end
