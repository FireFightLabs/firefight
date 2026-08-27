class IncidentType < ApplicationRecord
  include ConfigurableOption

  has_many :incidents, dependent: :restrict_with_error

  NOUN = "type".freeze
end
