module Integrations
  module ReadGuards
    # api_read only ever sends a GET to one of Google Cloud's APIs, named by its host's first label (run for
    # run.googleapis.com), so what the guard settles is which GETs answer secrets. Secret Manager's access method is a GET
    # answering a secret's value (secretmanager.projects.secrets.versions.access, Secret Manager API reference), and
    # alt=media answers a stored object's bytes rather than its description (Cloud Storage JSON API, objects.get), so
    # neither is read. Environment variables, and an instance's metadata, where startup scripts and keys are kept, are read
    # as their names.
    module GoogleCloud
      extend PathReads

      SERVICE = "service".freeze
      SERVICE_NAME = /\A[a-z][a-z0-9-]{1,62}\z/
      MEDIA = "media".freeze
      REFUSED = {
        /:access\z/ => "Secret Manager's access answers a secret's value, so a read never fetches it. Listing a secret's " \
                       "versions names each one with its state and when it was made."
      }.freeze
      # No path of Google's APIs answers nothing but secret values once access is refused.
      SECRET_PATHS = /(?!)/
      PROJECT = %r{(?:\A|/)projects/([^/:]+)}
      # Where an instance keeps its startup script and keys (Compute Engine API reference, Instance metadata).
      METADATA = "metadata".freeze
      ITEMS = "items".freeze

      def self.reading(tool_name, arguments)
        service = arguments[SERVICE].to_s.strip.downcase
        raise Refused, "service must be the first part of the API's host, such as run for run.googleapis.com." unless service.match?(SERVICE_NAME)

        super.merge(SERVICE => service)
      end

      def self.reads?(tool_name, arguments)
        arguments[SERVICE].to_s.strip.downcase.match?(SERVICE_NAME) && super
      end

      def self.refusal(path, query)
        return "alt=media answers a stored object's contents, which are data rather than configuration, so a read never fetches them." if query["alt"] == MEDIA

        super
      end

      # Every project a path names, such as faylee of /v2/projects/faylee/locations/europe-west1/services.
      def self.projects_in(path) = path.scan(PROJECT).flatten.uniq

      def self.hidden(value)
        case value
        when Hash
          value.to_h do |key, inner|
            [ key, key == METADATA && inner.is_a?(Hash) && inner[ITEMS].is_a?(Array) ? inner.merge(ITEMS => ApiReads.names_only(inner[ITEMS])) : hidden(inner) ]
          end
        when Array then value.map { |inner| hidden(inner) }
        else value
        end
      end
    end
  end
end
