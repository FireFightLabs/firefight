module AlertProviders
  # Generic webhook adapter. Verification is a shared-secret token compare
  # (Authorization: Bearer <token> or X-Firefight-Token header; every tool
  # can set one of those). Field extraction uses dot-path lookups into the
  # payload, overridable per source via config["field_map"]
  # (e.g. { "title" => "alert.name" }).
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
      return [] unless payload.is_a?(Hash)

      field_map = DEFAULT_FIELD_MAP.merge(source.config.fetch("field_map", {}))

      fields = field_map.each_with_object({}) do |(field, path), extracted|
        value = payload.dig(*path.split("."))
        extracted[field] = value.to_s if value.present?
      end
      fields["status"] = normalize_status(fields["status"])

      [ item(fields, payload) ]
    end
  end
end
