# A workspace-level choice of model for one purpose, or for every purpose
# when the purpose is AiPurpose::ANY. Set by operators, never from the
# dashboard. Provider is only needed for a model the registry does not know.
class AiModelOverride < ApplicationRecord
  belongs_to :workspace

  validates :purpose, inclusion: { in: AiPurpose::OVERRIDABLE }, uniqueness: { scope: :workspace_id }
  validates :model, presence: true

  scope :for_purpose, ->(purpose) { where(purpose: [ purpose, AiPurpose::ANY ]) }
end
