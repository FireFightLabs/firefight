module AlertProviders
  # normalize returns an array because providers like Alertmanager batch alerts per POST.
  # Each item carries only its own slice of the body.
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
