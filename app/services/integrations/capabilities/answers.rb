module Integrations
  module Capabilities
    # What adapters share when they read a remote server's answer or write its arguments: the parameters a connected tool
    # reports, the time and the limit asked for, the answer as text or data, and the shapes every capability returns with
    # the link the result carried. An adapter cites where its tools, arguments and answers come from, and uses these so
    # that each reads the same way.
    module Answers
      module_function

      # The parameters the connected tool reports, or nil when there is no tool to ask, as when only a refusal is wanted.
      def properties(tool) = tool&.params_schema.to_h.fetch("properties", nil)

      # The first of names the connected tool takes, or nil.
      def named(tool, names) = names.find { |name| properties(tool)&.key?(name) }

      # A tool that does not take an argument Firefight writes for it is one Firefight does not know, so the call is
      # refused in words rather than sent half understood.
      def known!(tool, arguments, provider)
        properties = properties(tool)
        missing = properties ? arguments.keys.reject { |name| properties.key?(name) } : []
        return arguments if missing.empty?

        raise Unroutable, "#{provider}'s #{tool.name} takes its arguments in a way Firefight does not know (no #{missing.join(', ')}), " \
                          "so ask it with #{provider}'s own tools."
      end

      # Minutes back from now when only minutes were asked, at most a week, or nil when a start or end was given.
      def minutes(given)
        return unless given["start"].blank? && given["end"].blank?

        [ given["minutes"].to_i.positive? ? given["minutes"].to_i : DEFAULT_MINUTES, MAX_MINUTES ].min
      end

      # The range asked for, as times, from minutes or a start and end.
      def range(given) = Telemetry.range(given, default_minutes: DEFAULT_MINUTES, max_minutes: MAX_MINUTES)

      # How many to ask for: what was asked, else default, and never more than most.
      def limit(given, most, default: most) = given["limit"].to_i.positive? ? [ given["limit"].to_i, most ].min : default

      # What the server said, without the line Firefight added linking back to its page.
      def text(result) = Array(result["content"]).filter_map { |part| part["text"] unless Telemetry.link_line?(part["text"]) }.join("\n")

      # The first part of the answer that is a JSON object or list, or the structured answer the tool gave, or nil. Some
      # servers add a note after the data.
      def data(result)
        structured = result["structuredContent"]
        return structured if structured.is_a?(Hash) || structured.is_a?(Array)

        Array(result["content"]).each do |part|
          next if part["text"].blank? || Telemetry.link_line?(part["text"])

          parsed = JSON.parse(part["text"])
          return parsed if parsed.is_a?(Hash) || parsed.is_a?(Array)
        rescue JSON::ParserError
          next
        end
        nil
      end

      # The answer read by the block into the shapes every capability returns. An error, an answer that is not data, or
      # one in a shape the provider's source did not lead Firefight to expect reaches the agent as it came.
      def read(result, provider)
        return result if result.nil? || result["isError"]

        body = data(result)
        body.nil? ? result : yield(body) || result
      rescue StandardError => error
        Rails.logger.warn({ event: "capability.unread_answer", provider: provider, error: error.class.name }.to_json)
        result
      end

      # The shapes every capability returns, keeping the line that links back to the provider, which SourceLinks added.
      def presented(result, text, charts: [])
        shaped = Telemetry.result(text, link: nil, charts: charts)
        kept = Array(result["content"]).select { |part| Telemetry.link_line?(part["text"]) }
        shaped.merge("content" => shaped["content"] + kept)
      end

      # The link SourceLinks added to the result, for a chart to open.
      def linked(result)
        line = Array(result["content"]).find { |part| Telemetry.link_line?(part["text"]) }
        url = line && line["text"].split(": ").last.to_s.strip
        url.presence
      end

      # The resource's own page on the map, as a link, or nil.
      def page(resource, provider) = resource.url.present? ? Telemetry::Link.new(provider: provider, url: resource.url) : nil

      # A time from seconds, milliseconds, microseconds or nanoseconds since the epoch, told apart by size, or from ISO
      # 8601 text.
      def time_of(value)
        return if value.blank?

        number = value.is_a?(Numeric) ? value : (Integer(value.to_s, exception: false) if value.to_s.match?(/\A\d+\z/))
        return Telemetry.parse_time(value)&.utc unless number

        seconds = if number > 10**17 then number / 1_000_000_000r
        elsif number > 10**14 then number / 1_000_000r
        elsif number > 10**11 then number / 1_000r
        else number
        end
        Time.zone.at(seconds).utc
      end
    end
  end
end
