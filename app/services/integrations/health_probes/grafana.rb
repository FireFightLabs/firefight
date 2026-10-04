module Integrations
  module HealthProbes
    # A Grafana MCP server answers a ping without reaching Grafana, so the health check also lists Grafana's datasources,
    # which only works when the server reaches Grafana with its token. It learns the Loki, Prometheus and Tempo
    # datasources Firefight's reads go to, each type also as a list a person chooses from on the connection's details,
    # and Grafana's own address, which its links open. The tools, their arguments and their answers are from
    # grafana/mcp-grafana (tools/datasources.go for list_datasources, tools/navigation.go for generate_deeplink).
    class Grafana < RemoteReader
      LIST_DATASOURCES = "list_datasources".freeze
      GENERATE_DEEPLINK = "generate_deeplink".freeze
      LOKI = "loki".freeze
      PROMETHEUS = "prometheus".freeze
      TEMPO = "tempo".freeze
      # Datasource types by the plugin id Grafana gives them. Only these speak LogQL, PromQL and TraceQL as Grafana's own do.
      TYPES = [ LOKI, PROMETHEUS, TEMPO ].freeze
      # Every Grafana tool that reads a datasource names it by this argument.
      DATASOURCE_ARG = "datasourceUid".freeze
      DATASOURCES = "datasources".freeze
      ADDRESS = "address".freeze
      # list_datasources answers at most 100 a page.
      PER_PAGE = 100
      MAX_PAGES = 5
      EXPLORE = "/explore".freeze

      # The datasources of a type the health check found, each a uid, name, type and whether it is the default.
      def self.datasources(settings, type)
        Array(settings&.learned&.dig(DATASOURCES)).select { |source| source["type"] == type }
      end

      # The connect field a person chooses each type's datasource in, on the connection's details.
      CHOSEN = { LOKI => "logs_datasource", PROMETHEUS => "metrics_datasource", TEMPO => "traces_datasource" }.freeze

      # The one datasource of a type Firefight reads, which is the one a person chose, else the only one, else Grafana's
      # default. nil when there is none, or several with none chosen and none the default, since a guess would read the
      # wrong place.
      def self.datasource(settings, type)
        found = datasources(settings, type)
        chosen = settings&.field(CHOSEN.fetch(type))
        return found.find { |source| source["uid"] == chosen } if chosen.present? && found.any? { |source| source["uid"] == chosen }

        found.one? ? found.first : found.find { |source| source["default"] }
      end

      # Grafana's address as Grafana gave it, such as https://acme.grafana.net, or nil when it has not been read.
      def self.address(settings) = settings&.learned&.dig(ADDRESS).presence

      # Raises Refused with Grafana's own words when the server cannot reach Grafana. With list_datasources switched off,
      # the ping alone decides and nothing new is learned.
      def check!
        sources = listed
        return if sources.nil?

        kept = sources.select { |source| TYPES.include?(source["type"]) }.map do |source|
          { "uid" => source["uid"], "name" => source["name"], "type" => source["type"], "default" => source["isDefault"] == true }
        end
        choices = TYPES.index_with do |type|
          kept.select { |source| source["type"] == type }.map { |source| { "value" => source["uid"], "label" => source["name"].presence || source["uid"] } }
        end
        { DATASOURCES => kept, ADDRESS => self.class.address(settings) || learned_address(kept.first), **choices }.compact
      end

      private

      def listed
        rows = []
        MAX_PAGES.times do |page|
          result = call(LIST_DATASOURCES, { "limit" => PER_PAGE, "offset" => page * PER_PAGE })
          return nil if result.nil?

          body = parsed(result)
          rows.concat(Array(body["datasources"]))
          return rows unless body["hasMore"] == true
        end
        rows
      end

      def parsed(result)
        refused!(LIST_DATASOURCES, result)
        body = Capabilities::Answers.data(result)
        raise Refused, "Grafana answered its datasources in a shape Firefight does not know." unless body.is_a?(Hash)

        body
      end

      # generate_deeplink writes Grafana's own address in front of every link it makes, so an Explore link for any
      # datasource gives the address. Without the tool, or a datasource, links are left out rather than guessed.
      def learned_address(source)
        return unless source

        result = call(GENERATE_DEEPLINK, { "resourceType" => "explore", DATASOURCE_ARG => source["uid"] })
        return if result.nil? || result["isError"]

        link = Capabilities::Answers.text(result).strip
        cut = link.index(EXPLORE)
        address = cut && link[0...cut]
        uri = URI.parse(address.to_s)
        address if uri.is_a?(URI::HTTP) && uri.host.present? && uri.query.nil? && uri.userinfo.nil?
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
