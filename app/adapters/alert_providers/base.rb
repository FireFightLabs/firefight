module AlertProviders
  # Adapter contract: verify the request came from the configured source, then
  # normalize the provider payload into an ARRAY of items (providers like
  # Alertmanager batch multiple alerts per POST). Each item is
  # { fields: {...}, payload: <that item's slice of the body> } so a batch of
  # N alerts stores N slices, not N copies of the whole body. Adapters are
  # thin boundary normalizers: no business logic, no persistence.
  class Base
    NORMALIZED_FIELDS = %w[external_id fingerprint status title description service severity_raw team environment].freeze

    RESOLVED_STATUS_VALUES = %w[resolved resolve ok recovered closed].freeze

    def self.verify(headers:, raw_body:, source:)
      raise NotImplementedError
    end

    def self.normalize(payload, source:)
      raise NotImplementedError
    end

    def self.normalize_status(value)
      RESOLVED_STATUS_VALUES.include?(value.to_s.downcase.strip) ? Alert::STATUS_RESOLVED : Alert::STATUS_FIRING
    end

    def self.item(fields, payload)
      { fields: fields, payload: payload }
    end
  end
end
