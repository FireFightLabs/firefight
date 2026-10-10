module Integrations
  module ReadGuards
    # api_read only ever sends a GET to Tinybird's API (tinybird.co/docs/api-reference), so what the guard settles is which
    # GETs answer secrets. The Tokens API answers each token itself, the Environment Variables API each variable's value,
    # and connections to Kafka, S3 and the like their credentials, so they are read as names. A token in any other answer is
    # replaced by the provider's own pattern (Providers::Tinybird).
    module Tinybird
      extend PathReads

      REFUSED = {
        %r{\A(?!/v[01]/)} => "Tinybird's API paths start /v0 or /v1, such as /v0/pipes."
      }.freeze
      SECRET_PATHS = %r{\A/v0/(tokens|variables|env|connectors|connections)(/|\z)}
    end
  end
end
