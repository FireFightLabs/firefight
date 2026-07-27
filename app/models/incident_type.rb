class IncidentType < ApplicationRecord
  include ConfigurableOption

  NOUN = "type".freeze

  scope :default_type, -> { active.find_by(is_default: true) }
end
