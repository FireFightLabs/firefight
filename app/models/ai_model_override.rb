# A workspace's model for one purpose, or for every purpose with
# AiPurpose::ANY. Operator data, never set from the dashboard.
class AiModelOverride < ApplicationRecord
  belongs_to :workspace

  validates :purpose, inclusion: { in: AiPurpose::OVERRIDABLE }, uniqueness: { scope: :workspace_id }
  validates :model, presence: true

  scope :for_purpose, ->(purpose) { where(purpose: [ purpose, AiPurpose::ANY ]) }
end
