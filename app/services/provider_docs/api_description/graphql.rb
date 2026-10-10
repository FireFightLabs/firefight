module ProviderDocs
  class ApiDescription
    # A GraphQL API's schema as introspection writes it. Each field of the query type is a read, in the area of the type
    # it answers, with its arguments and that type's fields. Mutations and subscriptions are left out, since a general
    # read never sends one.
    class Graphql
      WRAPPERS = %w[NON_NULL LIST].freeze
      # A paged list answers its rows inside edges and node, so the area and fields are the row's.
      CONNECTION = /Connection\z/

      def initialize(document, definition)
        @schema = document.dig("data", "__schema") || document["__schema"] || {}
        @definition = definition
        @types = Array(@schema["types"]).index_by { |type| type["name"] }
      end

      def title = "#{@definition.provider.humanize} GraphQL API"

      def preface = "Each read is a field of the query type, sent as a GraphQL query with its arguments as variables."

      def reads
        query = @types[@schema.dig("queryType", "name")]
        Array(query&.dig("fields")).map do |field|
          answered = row_type(base_name(field["type"]))
          parameters = Array(field["args"]).map do |arg|
            Parameter.new(name: arg["name"].to_s, where: "argument", type: written(arg["type"]), required: arg.dig("type", "kind") == "NON_NULL",
                          description: arg["description"].to_s)
          end
          Read.new(area: answered.presence || "Other", call: "query #{field['name']}", summary: "", description: field["description"].to_s,
                   parameters: parameters, answers: fields_of(answered))
        end
      end

      private

      def row_type(name)
        return name unless name.to_s.match?(CONNECTION)

        edge = base_name(Array(@types.dig(name, "fields")).find { |each| each["name"] == "edges" }&.dig("type"))
        base_name(Array(@types.dig(edge, "fields")).find { |each| each["name"] == "node" }&.dig("type")) || name
      end

      def fields_of(name) = Array(@types.dig(name, "fields")).map { |each| "#{each['name']} (#{written(each['type'])})" }

      def base_name(type)
        type = type["ofType"] while type.is_a?(Hash) && WRAPPERS.include?(type["kind"])
        type&.dig("name")
      end

      def written(type)
        return "" unless type.is_a?(Hash)

        case type["kind"]
        when "NON_NULL" then "#{written(type['ofType'])}!"
        when "LIST" then "[#{written(type['ofType'])}]"
        else type["name"].to_s
        end
      end
    end
  end
end
