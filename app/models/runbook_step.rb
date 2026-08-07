class RunbookStep < ApplicationRecord
  belongs_to :runbook
  has_many :incident_actions, dependent: :nullify

  validates :title, presence: true
  validates :position, presence: true

  scope :ordered, -> { order(:position) }
end
