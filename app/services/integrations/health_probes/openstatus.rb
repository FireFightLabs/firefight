module Integrations
  module HealthProbes
    # Lists OpenStatus's monitors through list_monitors, which only works with a key or sign in OpenStatus accepts, and
    # keeps each one's id, name and the address it checks, so a hostname on the map finds the monitors that watch it.
    # The tool, its paging and its answer are from openstatusHQ/openstatus
    # (packages/services/src/agent-tools/monitor.ts).
    class Openstatus < RemoteReader
      LIST_MONITORS = "list_monitors".freeze
      PER_PAGE = 50
      MAX_PAGES = 10

      def self.monitors(settings) = Array(settings&.learned.to_h["monitors"])

      # A list past MAX_PAGES keeps its first pages and says in the log that it was cut short.
      def check!
        listed = Pages.read(max_pages: MAX_PAGES) do |page|
          page ||= 1
          result = call(LIST_MONITORS, { "page" => page, "perPage" => PER_PAGE })
          return if result.nil?

          body = answered(result)
          items = body["items"].filter_map { |item| { "id" => item["id"], "name" => item["name"], "url" => item["url"] } if item.is_a?(Hash) && item["id"] }
          [ items, (page + 1 if page < body.dig("pagination", "totalPages").to_i) ]
        end
        Rails.logger.warn({ event: "health_probe.cut_short", probe: self.class.name, kept: listed.items.size }.to_json) if listed.incomplete?
        { "monitors" => listed.items }
      end

      private

      def answered(result)
        refused!(LIST_MONITORS, result)

        body = Capabilities::Answers.data(result)
        raise Refused, "OpenStatus answered its monitors in a shape Firefight does not read." unless body.is_a?(Hash) && body["items"].is_a?(Array)

        body
      end
    end
  end
end
