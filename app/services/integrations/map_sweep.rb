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

    # What a connection says when its sweep failed in a way no provider explained, such as an answer Firefight could not read.
    UNEXPECTED = "Firefight could not read this connection onto the map because of an unexpected error, so the map keeps " \
                 "what it had. It tries again at the next hourly sweep.".freeze

    # Whether the hourly schedule should sweep it now. The slack keeps a daily reader from slipping to the next day.
    SLACK = 10.minutes

    def self.due?(environment_row)
      swept = environment_row.map_swept_at
      swept.nil? || swept <= environment_row.integration.executor.map_every(environment_row.integration).ago + SLACK
    rescue Integrations::Error
      false
    end

    def self.run!(environment_row)
      snapshot = environment_row.integration.executor.map_of(environment_row)
      return false unless snapshot

      snapshot = Provider.for(environment_row.integration.provider).in_firefight_words(snapshot)
      changed = ResourceMap.record!(environment_row, snapshot)
      ResourceMap::CodeDefinitions.new(environment_row.integration.workspace).record!(environment_row, snapshot.code_files, read_in_full: snapshot.code_read)
      written!(environment_row, changed)
      true
    rescue Integrations::Error => error
      environment_row.update!(map_error: error.message)
      false
    end

    # What follows every write of the map, a sweep or a re-read after a change event (MapEvents): search indexes what
    # changed in one job and the matchers run again for the workspace, linking what settings name exactly
    # (ResourceMap::HostMatcher) and suggesting the rest. Anything else that reads the map as a whole after
    # it changes joins here, so both paths keep it.
    def self.written!(environment_row, changed)
      SearchDocument.index_later(ResourceMap::Resource, changed)
      ResourceMap::Matcher.new(environment_row.integration.workspace).run!
    end
  end
end
