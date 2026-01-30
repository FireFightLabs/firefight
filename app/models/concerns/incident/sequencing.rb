# frozen_string_literal: true

# Incident::Sequencing - Sequential numbering and identifier generation
#
# Handles workspace-scoped sequential incident numbers with row-level locking
# to prevent race conditions during concurrent incident creation.
#
# Generates identifiers in format: INC-001, INC-002, etc.
#
module Incident::Sequencing
  extend ActiveSupport::Concern

  included do
    before_validation :assign_sequence_number, on: :create
    before_validation :generate_identifier, on: :create
  end

  private

  # Sequential number generation with row-level locking
  def assign_sequence_number
    return if sequence_number.present?

    Incident.transaction do
      # Get max sequence number without lock (aggregate functions can't be locked)
      # Lock is on the workspace to prevent race conditions during sequential number assignment
      workspace.lock!
      max_seq = workspace.incidents.maximum(:sequence_number) || 0
      self.sequence_number = max_seq + 1
    end
  end

  def generate_identifier
    self.identifier = "INC-#{sequence_number.to_s.rjust(3, '0')}"
  end
end
