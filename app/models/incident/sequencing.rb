module Incident::Sequencing
  extend ActiveSupport::Concern

  included do
    before_validation :assign_sequence_number, on: :create
    before_validation :generate_identifier, on: :create
  end

  private

  def assign_sequence_number
    return if sequence_number.present?

    Incident.transaction do
      # The workspace row is the lock, an aggregate cannot be locked itself.
      workspace.lock!
      max_seq = workspace.incidents.maximum(:sequence_number) || 0
      self.sequence_number = max_seq + 1
    end
  end

  def generate_identifier
    self.identifier = "INC-#{sequence_number.to_s.rjust(3, '0')}"
  end
end
