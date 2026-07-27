class IncidentType < ApplicationRecord
  include ConfigurableOption
  include DefaultableOption

  has_many :incidents, dependent: :restrict_with_error

  NOUN = "type".freeze

  scope :default_type, -> { active.find_by(is_default: true) }
end
