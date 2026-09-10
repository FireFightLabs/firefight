module Incident::Metrics
  extend ActiveSupport::Concern

  def time_to_resolve
    return nil unless resolved_at
    ((resolved_at - declared_at) / 60).round
  end
end
