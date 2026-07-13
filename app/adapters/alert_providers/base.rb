module AlertProviders
  # Adapter contract: verify the request came from the configured source, then
  # normalize the provider payload into an ARRAY of field hashes (providers
  # like Alertmanager batch multiple alerts per POST). Adapters are thin
  # boundary normalizers — no business logic, no persistence.
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
      RESOLVED_STATUS_VALUES.include?(value.to_s.downcase) ? Alert::STATUS_RESOLVED : Alert::STATUS_FIRING
    end
  end
end
