module ProviderDocs
  class ApiDescription
    # An OpenAPI 3 or Swagger 2 description. Each GET is a read, in the area of its first tag or else its path's first
    # segment, with its path written after relative_to when the source names one, as the provider's general read takes it.
    class OpenApi
      GET = "get".freeze
      SUCCESS = /\A2\d\d\z/
      API_VERSION = "api-version".freeze
      SHARED_API_VERSION = %r{\A\.\./.*/ApiVersionParameter\z}

      def initialize(document, definition)
        @document = document
        @definition = definition
      end

      def title = @document.dig("info", "title").presence || "#{@definition.provider.humanize} API"

      def preface
        base = server
        "Every path is a GET#{" to #{base}" if base}#{", written after #{relative_to}" if relative_to}."
      end

      def reads
        @document.fetch("paths", {}).flat_map do |path, item|
          operation = item.is_a?(Hash) ? item[GET] : nil
          next [] unless operation.is_a?(Hash)

          shown = shown_path(path)
          next [] if shown.nil?

          [ Read.new(area: area_of(operation, shown), call: "GET #{shown}", summary: (operation["summary"].presence || operation["operationId"]).to_s, description: operation["description"].to_s,
                     parameters: parameters_of(item, operation), answers: answers_of(operation)) ]
        end
      end

      private

      def relative_to = @definition["relative_to"]

      def server
        url = Array(@document["servers"]).first&.dig("url")
        url ||= "https://#{@document['host']}#{@document['basePath']}" if @document["host"].present?
        url
      end

      def shown_path(path)
        return path if relative_to.blank?

        path.start_with?(relative_to) ? "/#{path.delete_prefix(relative_to).delete_prefix('/')}" : nil
      end

      def area_of(operation, path) = Array(operation["tags"]).first.presence || path.split("/").compact_blank.first || "root"

      # The path's own parameters and the operation's, the operation's winning, without the header ones a client sends.
      # Azure's descriptions take api-version from a shared file they do not carry, so it is named with the version this
      # description is of, which is the value it takes.
      def parameters_of(item, operation)
        listed = Array(item["parameters"]) + Array(operation["parameters"])
        given = listed.map { |each| resolved(each) }.select { |each| each.is_a?(Hash) }
        if listed.any? { |each| each.is_a?(Hash) && each["$ref"].to_s.match?(SHARED_API_VERSION) }
          given << { "name" => API_VERSION, "in" => "query", "required" => true, "schema" => { "type" => "string", "enum" => [ @document.dig("info", "version") ].compact } }
        end
        given.reverse.uniq { |each| [ each["name"], each["in"] ] }.reverse.filter_map do |each|
          next if %w[header cookie body].include?(each["in"]) || each["name"].blank?

          schema = resolved(each["schema"] || {})
          Parameter.new(name: each["name"].to_s, where: each["in"].to_s, type: type_of(schema.presence || each),
                        required: each["required"] == true, description: each["description"].to_s)
        end
      end

      # The top fields of a successful answer, or of each item when it answers a list.
      def answers_of(operation)
        success = operation.fetch("responses", {}).find { |code, _| code.to_s.match?(SUCCESS) }&.last
        success = resolved(success)
        return [] unless success.is_a?(Hash)

        schema = success["schema"] || success.dig("content", "application/json", "schema") || success["content"]&.values&.first&.dig("schema")
        schema = resolved(schema)
        schema = resolved(schema["items"]) if schema.is_a?(Hash) && schema["type"] == "array"
        fields_of(schema)
      end

      def fields_of(schema, depth = 0)
        return [] unless schema.is_a?(Hash) && depth < 4

        own = schema.fetch("properties", {}).map { |name, inner| "#{name} (#{type_of(resolved(inner))})" }
        own + Array(schema["allOf"]).flat_map { |part| fields_of(resolved(part), depth + 1) }
      end

      def type_of(schema)
        return "" unless schema.is_a?(Hash)

        type = Array(schema["type"]).first.to_s
        type = "#{type_of(resolved(schema['items']))} list" if type == "array" && schema["items"]
        enum = Array(schema["enum"]).first(12)
        enum.any? ? "#{type}, one of #{enum.join(', ')}" : type
      end

      # A local $ref followed to what it names, at most a few deep so a reference to itself ends.
      def resolved(value, depth = 0)
        return value unless value.is_a?(Hash) && value["$ref"].is_a?(String) && depth < 8

        target = value["$ref"].delete_prefix("#/").split("/").map { |part| part.gsub("~1", "/").gsub("~0", "~") }
        found = target.empty? ? nil : @document.dig(*target)
        resolved(found, depth + 1) || {}
      end
    end
  end
end
