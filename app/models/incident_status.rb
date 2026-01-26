class IncidentStatus < ApplicationRecord
  CATEGORY_LIVE = "live"
  CATEGORY_CLOSED = "closed"
  CATEGORIES = [ CATEGORY_LIVE, CATEGORY_CLOSED ].freeze

  belongs_to :workspace
  has_many :incidents, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }
  validates :category, inclusion: { in: CATEGORIES }
  validates :position, presence: true, numericality: { only_integer: true }

  scope :active, -> { where(deleted_at: nil) }
  scope :live, -> { where(category: CATEGORY_LIVE) }
  scope :closed, -> { where(category: CATEGORY_CLOSED) }
  scope :ordered, -> { order(:position) }
  scope :default_status, -> { find_by(is_default: true) }

  def live?
    category == CATEGORY_LIVE
  end

  def closed?
    category == CATEGORY_CLOSED
  end
end
