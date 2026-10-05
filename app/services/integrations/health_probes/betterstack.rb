module Integrations
  module HealthProbes
    # Lists Better Stack's uptime monitors through its monitors tool, which only works with a token or sign in Better
    # Stack accepts, and keeps each one's id, name and the address it checks, so a hostname on the map finds the
    # monitors that watch it. The tool's name is from Better Stack's MCP documentation
    # (betterstack.com/docs/getting-started/integrations/mcp). Its answer is read in the shape Better Stack's Uptime API
    # documents for listing monitors (data, each with an id and attributes holding url and pronounceable_name). An answer
    # in another shape is no failure. It teaches nothing, and what was learned before is kept.
    class Betterstack < RemoteReader
      MONITORS = "monitors".freeze

      def self.monitors(settings) = Array(settings&.learned.to_h["monitors"])

      def check!
        result = call(MONITORS)
        return if result.nil?
        refused!(MONITORS, result)

        body = Capabilities::Answers.data(result)
        items = body.is_a?(Hash) ? body["data"] : nil
        return unless items.is_a?(Array)

        { "monitors" => items.filter_map do |item|
          attributes = item.is_a?(Hash) ? item["attributes"].to_h : {}
          { "id" => item["id"].to_s, "name" => attributes["pronounceable_name"], "url" => attributes["url"] } if item.is_a?(Hash) && item["id"].present?
        end }
      end
    end
  end
end
