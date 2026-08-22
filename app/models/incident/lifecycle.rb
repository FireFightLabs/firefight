# Incident::Lifecycle - Status transitions and lifecycle management
#
# Handles incident lifecycle state changes:
# - Auto-setting declared_at timestamp on creation
# - Stage-driven timestamp side effects (resolved_at, next_update_at)
#
module Incident::Lifecycle
  extend ActiveSupport::Concern

  included do
    before_validation :set_declared_at, on: :create
    before_save :apply_lifecycle_side_effects
  end

  private

  def set_declared_at
    self.declared_at ||= Time.current
  end

  def apply_lifecycle_side_effects
    apply_resolved_at

    # An incident that is over is never waiting on a next update, whichever
    # save put it there. Checked on every save rather than only on a status
    # change, so a write that sets a reminder on an already-terminal incident
    # cannot leave one behind.
    self.next_update_at = nil if next_update_at.present? && terminal?
  end

  def apply_resolved_at
    return unless incident_status_id_changed?

    stage = incident_status.incident_lifecycle_stage

    if stage.closed?
      self.resolved_at ||= Time.current
    elsif stage.active? || stage.triage?
      self.resolved_at = nil if resolved_at.present?
    end
  end
end
