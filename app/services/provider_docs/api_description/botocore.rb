module ProviderDocs
  class ApiDescription
    # An AWS service's description as AWS's SDKs are built from it (botocore's service-2.json). Each operation named
    # Describe, List, Get or BatchGet is a read, written by its name and its name in AWS's SDK for Ruby, which is how the
    # AWS general read takes it, with its input members by their SDK names.
    class Botocore
      READ = /\A(Describe|List|Get|BatchGet)[A-Z]/

      def initialize(document, definition)
        @document = document
        @definition = definition
      end

      def title = "#{@document.dig('metadata', 'serviceFullName') || @document.dig('metadata', 'serviceId')} (#{service})"

      def preface = "Each read is an operation of the #{service} service, called by its name with its input as parameters."

      def reads
        @document.fetch("operations", {}).values.filter_map do |operation|
          name = operation["name"].to_s
          next unless name.match?(READ)

          input = shape(operation.dig("input", "shape"))
          required = Array(input["required"])
          parameters = input.fetch("members", {}).map do |member, each|
            Parameter.new(name: underscore(member), where: "input", type: shape(each["shape"])["type"].to_s, required: required.include?(member),
                          description: each["documentation"].to_s)
          end
          answers = shape(operation.dig("output", "shape")).fetch("members", {}).map { |member, each| "#{underscore(member)} (#{shape(each['shape'])['type']})" }
          Read.new(area: service, call: "#{name} (#{underscore(name)})", summary: "", description: operation["documentation"].to_s,
                   parameters: parameters, answers: answers)
        end
      end

      private

      def service = @definition["service"].presence || @document.dig("metadata", "endpointPrefix").to_s

      def shape(name) = name ? @document.dig("shapes", name.to_s) || {} : {}

      def underscore(name) = name.to_s.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end
  end
end
