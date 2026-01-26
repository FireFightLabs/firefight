# frozen_string_literal: true

# Incident::Lifecycle - Status transitions and lifecycle management
#
# Handles incident lifecycle state changes:
# - Auto-setting declared_at timestamp on creation
# - Auto-setting resolved_at when status moves to closed category
#
module Incident::Lifecycle
  extend ActiveSupport::Concern

  included do
    before_validation :set_declared_at, on: :create
    before_save :update_resolved_at
  end

  private

  def set_declared_at
    self.declared_at ||= Time.current
  end

  # Auto-set resolved_at when status changes to closed category
  # Clear resolved_at when reopening incident
  def update_resolved_at
    if incident_status_id_changed?
      if incident_status.closed? && resolved_at.nil?
        self.resolved_at = Time.current
      elsif incident_status.live? && resolved_at.present?
        self.resolved_at = nil
      end
    end
  end
end
