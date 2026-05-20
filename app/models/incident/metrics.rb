# frozen_string_literal: true

# Incident::Metrics - Incident analytics and calculations
#
# Provides read-only calculations for incident metrics and analytics:
# - Time to resolve
# - Future: SLA compliance, escalation counts, response times, etc.
#
module Incident::Metrics
  extend ActiveSupport::Concern

  # Time to resolve in minutes
  def time_to_resolve
    return nil unless resolved_at
    ((resolved_at - declared_at) / 60).round # minutes
  end
end
