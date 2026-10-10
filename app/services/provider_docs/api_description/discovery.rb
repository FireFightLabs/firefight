module ProviderDocs
  class ApiDescription
    # A Google API Discovery document. Each method with httpMethod GET is a read, in the area of the resources it sits
    # under, with its path written as the API's host takes it after the service's own path, such as
    # /v2/projects/{projectsId}/locations/{locationsId}/services.
    class Discovery
      GET = "GET".freeze

      def initialize(document, definition)
        @document = document
        @definition = definition
      end

      def title = [ @document["title"].presence || @document["name"].to_s, @document["version"] ].compact_blank.join(" ")

      def preface = "Every path is a GET to #{@document['rootUrl']}, written as the path after the host."

      def reads = methods_in(@document["resources"], [])

      private

      def methods_in(resources, names)
        resources.to_h.flat_map do |name, resource|
          area = [ *names, name ].join(".")
          own = resource.fetch("methods", {}).values.filter_map { |method| read_of(area, method) if method["httpMethod"] == GET }
          own + methods_in(resource["resources"], [ *names, name ])
        end
      end

      def read_of(area, method)
        path = "/#{@document['servicePath']}#{method['flatPath'] || method['path']}".squeeze("/")
        parameters = method.fetch("parameters", {}).map do |name, each|
          Parameter.new(name: name, where: each["location"].to_s, type: [ each["type"], ("repeated" if each["repeated"]) ].compact.join(", "),
                        required: each["required"] == true, description: each["description"].to_s)
        end
        Read.new(area: area, call: "GET #{path}", summary: method["id"].to_s, description: method["description"].to_s,
                 parameters: parameters, answers: answers_of(method.dig("response", "$ref")))
      end

      def answers_of(schema_name)
        schema = @document.dig("schemas", schema_name.to_s)
        return [] unless schema.is_a?(Hash)

        schema.fetch("properties", {}).map { |name, each| "#{name} (#{each['type'] || each['$ref']})" }
      end
    end
  end
end
