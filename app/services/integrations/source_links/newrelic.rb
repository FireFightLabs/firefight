module Integrations
  module SourceLinks
    # An NRQL answer whose rows all name one New Relic entity links to that entity's page, at the permalink New Relic
    # documents for an entity (<site>/redirect/entity/<guid>, docs/apis/nerdgraph/examples/nerdgraph-workloads-api-tutorials).
    # The logs and deploys Firefight asks for select entity.guid so they can. An answer that names none, or several,
    # gets no link, since New Relic documents no address that opens a query. The site is the one of the region the
    # connection was made in, and a connection in no region Firefight knows gets no link rather than a guessed one.
    class Newrelic
      NAME = Capabilities::Newrelic::NAME
      GUID = "entity.guid".freeze
      # A GUID is base64, so it is matched as that and escaped into the address.
      GUID_FORMAT = %r{\A[A-Za-z0-9+/=]{8,200}\z}

      def initialize(settings)
        @site = settings.site
      end

      def link(tool_name:, arguments: {}, text: "")
        return unless @site && tool_name == Capabilities::Newrelic::NRQL_TOOL

        guids = Array(Capabilities::Newrelic.rows({ "content" => [ { "type" => "text", "text" => text } ] })).filter_map { |row| row[GUID] }.uniq
        return unless guids.one? && guids.first.to_s.match?(GUID_FORMAT)

        Telemetry::Link.new(provider: NAME, url: "#{@site.chomp('/')}/redirect/entity/#{ERB::Util.url_encode(guids.first)}")
      end
    end
  end
end
