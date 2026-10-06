module Integrations
  # One connection's daily read of its resources' usual log lines, so a slow provider never holds up another.
  class LogPatternReadJob < ApplicationJob
    queue_as :background
    limits_concurrency key: ->(environment_row, _resource_ids) { environment_row.id }, duration: 1.hour

    def perform(environment_row, resource_ids)
      LogPatternSweep.read!(environment_row, resource_ids)
    end
  end
end
