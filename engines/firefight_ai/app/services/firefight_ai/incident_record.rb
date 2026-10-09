module FirefightAi
  # An incident's timeline as prompt text, shared by every prompt that reads the record, so an update reads the same to
  # each. Events are Incident#to_full_context's hashes, an update carrying its message and its changes.
  module IncidentRecord
    module_function

    def timeline(events)
      events.map do |event|
        line = "- [#{event[:at]}] #{event[:description]} (by #{event[:by] || 'system'})"
        changes = Array(event[:changes]).map { |change| change_text(change) }
        line += ". Changed #{changes.join(', ')}" if changes.any?
        line += ". Posted the status update quoted under Status Updates" if event[:message].present?
        line
      end
    end

    # Each update's message in full, quoted so its own headings and lists stay inside it.
    def status_updates(events)
      posted = events.select { |event| event[:message].present? }
      return [] if posted.empty?

      lines = [ "\n## Status Updates", "What responders posted with each update, in order and in full." ]
      posted.each do |event|
        lines << "\n### #{event[:at]}, by #{event[:by] || 'system'}"
        lines << event[:message].to_s.split("\n", -1).map { |line| line.strip.empty? ? ">" : "> #{line}" }.join("\n")
      end
      lines
    end

    def change_text(change)
      before = change[:before].presence
      after = change[:after].presence
      if before && after then "#{change[:label]} from #{before} to #{after}"
      elsif after then "#{change[:label]} to #{after}"
      else "#{change[:label]} (cleared, was #{before})"
      end
    end

    def action_line(action)
      assignee = action[:assignee] ? " (assigned to #{action[:assignee]})" : ""
      link = [ action[:external_key], action[:external_url] ].compact.join(", ")
      link = " [#{link}]" if link.present?
      "- [#{action[:type]}] #{action[:description]}#{link}, #{action[:status]}#{assignee}"
    end
  end
end
