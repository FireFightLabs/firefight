module AlertProviders
  # Fields are dot-path lookups a source overrides through config["field_map"].
  # config["items_path"] naming an array turns each element into its own alert.
  class Generic < Base
    LABEL = "Generic webhook".freeze
    FIELD_MAPPING = true
    SETUP_STEPS = [
      "In your tool, add a webhook that sends alerts to this URL as a POST request with a JSON body.",
      "Send the token in an Authorization header as Bearer and the token, in a #{TOKEN_HEADER} header, or as the password " \
      "of HTTP Basic auth with any user name.",
      "Send a test alert, then map its fields below if they are not already named title, status, service and so on."
    ].freeze
    DEFAULT_FIELD_MAP = {
      "external_id" => "id",
      "fingerprint" => "fingerprint",
      "status" => "status",
      "title" => "title",
      "description" => "description",
      "service" => "service",
      "severity_raw" => "severity",
      "team" => "team",
      "environment" => "environment",
      "url" => "url"
    }.freeze

    def self.verify(headers:, raw_body:, source:)
      # A bare Authorization value without the Bearer scheme has always been accepted, so it still is.
      authorization = headers["Authorization"].to_s.delete_prefix("Bearer ").presence
      [ authorization, headers[TOKEN_HEADER].to_s.presence, basic_password(headers) ].compact.any? do |provided|
        token_matches?(provided, source)
      end
    end

    def self.normalize(payload, source:, headers: {})
      if (items_path = source.config["items_path"].presence)
        elements = resolve_path(payload, items_path)
        return [] unless elements.is_a?(Array)

        return elements.filter_map do |element|
          next unless element.is_a?(Hash)

          fields = extract(element, source)
          item(fields, element) if recognized?(fields)
        end
      end

      return [] unless payload.is_a?(Hash)

      fields = extract(payload, source)
      recognized?(fields) ? [ item(fields, payload) ] : []
    end

    def self.extract(payload, source)
      field_map = DEFAULT_FIELD_MAP.merge(source.config.fetch("field_map", {}))

      fields = field_map.each_with_object({}) do |(field, path), extracted|
        value = resolve_path(payload, path)
        extracted[field] = value.to_s if value.present?
      end
      fields["status"] = normalize_status(fields["status"])
      fields
    end

    # No mapped field resolving means noise, not an alert. The controller
    # turns an empty item list into a 422.
    def self.recognized?(fields)
      fields.except("status").any?
    end

    def self.resolve_path(payload, path)
      path.to_s.split(".").reduce(payload) do |node, segment|
        case node
        when Hash then node[segment]
        when Array then segment.match?(/\A\d+\z/) ? node[segment.to_i] : nil
        end
      end
    end
  end
end
