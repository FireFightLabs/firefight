module Integrations
  module MitigationReaders
    # api_request reaches the whole API, so a call is a mitigation when it pauses a service or an addon, or scales a
    # service to fewer instances than the map last read it running (to none counts whatever the map holds).
    module Northflank
      TOOL = "api_request".freeze
      PAUSE = %r{\A/?(services|addons)/[^/]+/pause\z}
      SCALE = %r{\A/?services/(?<id>[^/]+)/scale\z}

      def self.mitigation?(tool, arguments)
        return false unless tool.name == TOOL && arguments["method"].to_s.upcase == "POST"

        path = arguments["path"].to_s.strip
        return true if path.match?(PAUSE)

        scaled = path.match(SCALE)
        scaled.present? && fewer?(tool, scaled[:id], arguments.dig("body", "instances"))
      end

      def self.fewer?(tool, id, asked)
        asked = Integer(asked.to_s, exception: false)
        return false if asked.nil?
        return true if asked.zero?

        resource = ResourceMap::Resource.find_by(workspace_id: tool.integration.workspace_id, provider: Packs::Northflank::PROVIDER_KEY,
                                                 kind: ResourceMap::KIND_SERVICE, external_id: id)
        now = Integer(resource&.details.to_h["instances"].to_s, exception: false)
        !now.nil? && asked < now
      end
      private_class_method :fewer?
    end
  end
end
