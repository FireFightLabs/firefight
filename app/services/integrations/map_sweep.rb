module Integrations
  # Reads what one connection reaches onto the resource map. A provider that cannot be read leaves the map as it was and
  # says why on the connection, so a failed sweep never empties the map.
  class MapSweep
    # Queues a sweep of every connection in the workspace, for Sync now, and says how many.
    def self.queue_for(workspace)
      rows = IntegrationEnvironment.enabled.joins(:integration).merge(Integration.active).where(integrations: { workspace_id: workspace.id }).to_a
      rows.each { |row| MapSweepJob.perform_later(row) }
      rows.size
    end

    # Whether the hourly schedule should sweep it now. The slack keeps a daily reader from slipping to the next day.
    SLACK = 10.minutes

    def self.due?(environment_row)
      swept = environment_row.map_swept_at
      swept.nil? || swept <= environment_row.integration.executor.map_every(environment_row.integration).ago + SLACK
    end

    def self.run!(environment_row)
      snapshot = environment_row.integration.executor.map_of(environment_row)
      return false unless snapshot

      ResourceMap.record!(environment_row, snapshot)
      ResourceMap::Matcher.new(environment_row.integration.workspace).run!
      true
    rescue Integrations::Error => error
      environment_row.update!(map_error: error.message)
      false
    end
  end
end
