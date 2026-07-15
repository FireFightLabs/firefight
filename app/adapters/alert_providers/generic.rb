module AlertProviders
  # Generic webhook adapter. Verification is a shared-secret token compare
  # (Authorization: Bearer <token> or X-Firefight-Token header; every tool
  # can set one of those). Field extraction uses dot-path lookups into the
  # payload (numeric segments index into arrays), overridable per source via
  # config["field_map"] (e.g. { "title" => "alert.name" }). When
  # config["items_path"] points at an array (e.g. "alerts" for Alertmanager),
  # each element is normalized as its own alert with its own payload slice.
  class Generic < Base
    DEFAULT_FIELD_MAP = {
      "external_id" => "id",
      "fingerprint" => "fingerprint",
      "status" => "status",
      "title" => "title",
      "description" => "description",
      "service" => "service",
      "severity_raw" => "severity",
      "team" => "team",
      "environment" => "environment"
    }.freeze

    def self.verify(headers:, raw_body:, source:)
      provided = headers["Authorization"].to_s.delete_prefix("Bearer ").presence ||
                 headers["X-Firefight-Token"].to_s.presence
      return false if provided.blank?

      ActiveSupport::SecurityUtils.secure_compare(provided, source.secret_token)
    end

    def self.normalize(payload, source:)
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

    # A payload where no mapped field resolved is noise, not an alert; the
    # controller turns an empty item list into a diagnosable 422.
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
