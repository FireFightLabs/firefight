module Integrations
  # Calls to Turso's Platform API (https://api.turso.tech/v1, docs.turso.tech/api-reference) with a connection's own
  # token, sent as it is held, Bearer and the token.
  class TursoApi
    class Error < Integrations::Error; end
    # The token is not one the Platform API takes, or it may not read what was asked.
    class Refused < Error; end
    class NotFound < Error
      include Integrations::NotFound
    end

    ROOT = "https://api.turso.tech/v1".freeze
    REFUSALS = [ 401, 403 ].freeze

    def initialize(authorization)
      @authorization = authorization
    end

    # The organizations the token reaches (GET /organizations), each with its slug, name and type.
    def organizations = Array(get("/organizations")).select { |each| each.is_a?(Hash) }

    # A database's usage over a period (GET /organizations/{slug}/databases/{name}/usage), from and to in ISO 8601, the
    # current calendar month when left out. It answers the database's total and each instance's rows read and written,
    # storage and bytes synced.
    def usage(organization, database, from: nil, to: nil)
      query = { "from" => from, "to" => to }.compact
      path = "/organizations/#{Http.segment(organization)}/databases/#{Http.segment(database)}/usage"
      get(query.empty? ? path : "#{path}?#{URI.encode_www_form(query)}")["database"].to_h
    end

    private

    def get(path)
      uri = URI.parse("#{ROOT}#{path}")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = @authorization
      Http.json(uri, request, error_class: Error, provider_name: "Turso",
                              refine: lambda { |code, _said|
                                if REFUSALS.include?(code) then Refused
                                elsif code == 404 then NotFound
                                end
                              })
    end
  end
end
