module Integrations
  # Once a day, after what normal looks like, what each resource worth knowing usually logs. It reads a resource's logs
  # through the logs capability, the same route a person or Halon asks by, so no provider needs code of its own. It
  # reads half an hour on each of several days across the week, each at another hour, up to LINES lines each. The lines are mined
  # into patterns (ResourceMap::LogMiner) and kept (ResourceMap::LogTemplate). Every call is the map sweep's, recorded in
  # the activity log like its other reads, and only switched on tools are called. A resource whose logs no connection
  # reads has none, and its panel says why.
  class LogPatternSweep
    WINDOWS = 6
    WINDOW_LENGTH = 30.minutes
    # Each window ends this much earlier than the one before, so the samples fall on different days and hours.
    WINDOW_STEP = 26.hours
    LINES = 2_000
    PER_CONNECTION = 200

    # How many resources one connection's read covers a day, the same for every workspace for now.
    def self.per_connection = PER_CONNECTION

    # One plan per workspace, so a large map never holds up another.
    def self.queue_all
      ResourceMap::Resource.present.distinct.pluck(:workspace_id).each { |workspace_id| LogPatternSweepJob.perform_later(workspace_id) }
    end

    # Which connection reads each resource in scope, at most PER_CONNECTION resources a connection, each connection read
    # by its own job.
    def self.plan!(workspace)
      by_row = Hash.new { |hash, row| hash[row] = [] }
      ResourceMap::LogTemplate.scope_of(workspace).each do |resource|
        call = Capabilities.resolve_for(resource, Capabilities::LOGS, {})
        by_row[call.environment_row] << resource.id if by_row[call.environment_row].size < per_connection
      rescue Capabilities::Unroutable
        next
      end
      by_row.each { |row, ids| LogPatternReadJob.perform_later(row, ids) }
      by_row.size
    end

    # Reads and mines each resource. A rate limit stops the connection's read for the day, and any other failure keeps
    # that resource's patterns from before. What failed is the connection's log_patterns_error, shown with its other
    # problems on the map.
    def self.read!(environment_row, resource_ids, now: Time.current)
      failures = []
      ResourceMap::Resource.present.where(id: resource_ids).find_each do |resource|
        answered, lines = sample(resource, now)
        next unless answered

        ResourceMap::LogTemplate.record!(answered, resource, ResourceMap::LogMiner.mine(lines, keep: ResourceMap::LogTemplate::KEPT), at: now)
      rescue RateLimited => error
        failures = [ error.message ]
        break
      rescue Capabilities::Unroutable, Integrations::Error => error
        Rails.logger.warn("log_pattern_sweep.resource_failed resource=#{resource.id} error=#{error.message}")
        failures << error.message
      end
      environment_row.update!(log_patterns_error: failures.first)
    end

    # The lines of every window and the connection that answered them, or nil when none answered.
    def self.sample(resource, now)
      answered = nil
      lines = windows(now).flat_map do |from, to|
        call = Capabilities.resolve_for(resource, Capabilities::LOGS, { "start" => from.utc.iso8601, "end" => to.utc.iso8601, "limit" => LINES })
        used, result = read(call)
        answered ||= used
        result ? ResourceMap::LogMiner.lines_of(result).first(LINES) : []
      end
      [ answered, lines ]
    end

    def self.windows(now)
      1.upto(WINDOWS).map do |step|
        to = now - (step * WINDOW_STEP)
        [ to - WINDOW_LENGTH, to ]
      end
    end

    # The platform answers when the observability tool asked first has nothing, as it does for a person.
    def self.read(call)
      result = run(call)
      return [ call.environment_row, result ] if call.fallback.nil? || Capabilities.definitive?(result)

      fallback = run(call.fallback)
      return [ call.environment_row, result ] if fallback.nil?

      [ call.fallback.environment_row, fallback ]
    end

    # An answer that says it failed raises, so one provider's refusal is recorded as that resource's failure.
    def self.run(call)
      answer = call.tool.swept!(call.arguments) do
        call.tool.integration.executor.call(tool: call.tool, environment_row: call.environment_row, arguments: call.arguments)
      end
      presented = call.present_result(answer)
      return presented unless presented["isError"] == true

      raise Integrations::Error, Array(presented["content"]).filter_map { |part| part["text"] }.join("\n").lines.first.to_s.strip
    end
    private_class_method :sample, :windows, :read, :run
  end
end
