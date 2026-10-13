module Integrations
  # Counts every connection's tools again as a model is handed them (Integration#recount_tool_definitions!). Enqueued
  # once by the migration that added the stored length, whose plain SQL cannot read what a connection's environments
  # add, and run by hand with bin/rails integrations:recount_tool_definitions. Answers how many connections it counted.
  class ToolDefinitionRecountJob < ApplicationJob
    queue_as :background

    def perform
      counted = 0
      Integration.where(id: Integration::Tool.select(:integration_id)).find_each do |integration|
        integration.recount_tool_definitions!
        counted += 1
      end
      counted
    end
  end
end
