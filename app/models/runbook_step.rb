class RunbookStep < ApplicationRecord
  belongs_to :runbook

  validates :title, presence: true
  validates :position, presence: true

  scope :ordered, -> { order(:position) }
end
